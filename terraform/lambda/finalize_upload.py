import json
import os
import time
import uuid

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

BUCKET = os.environ["BUCKET_NAME"]
table = dynamodb.Table(os.environ["TABLE_NAME"])

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_BYTES = 5 * 1024 * 1024  # 5MB


def _req_id(event) -> str:
    return (event.get("requestContext") or {}).get("requestId") or str(uuid.uuid4())


def _user_sub(event):
    claims = (((event.get("requestContext") or {}).get("authorizer") or {}).get("jwt") or {}).get("claims") or {}
    return claims.get("sub")


def _log(level: str, msg: str, **fields):
    print(json.dumps({"level": level, "msg": msg, "ts": int(time.time()), **fields}))


def _cors_headers():
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "content-type,authorization",
    }


def _resp(status: int, body: dict):
    return {"statusCode": status, "headers": _cors_headers(), "body": json.dumps(body)}


def handler(event, context):
    rid = _req_id(event)

    method = (event.get("requestContext") or {}).get("http", {}).get("method", "")
    if method == "OPTIONS":
        return _resp(200, {"ok": True})

    sub = _user_sub(event)
    if not sub:
        return _resp(401, {"error": "Unauthorized", "requestId": rid})

    body = event.get("body") or "{}"
    try:
        data = json.loads(body)
    except Exception:
        return _resp(400, {"error": "Invalid JSON body", "requestId": rid})

    object_key = data.get("objectKey")
    if not object_key or not isinstance(object_key, str):
        return _resp(400, {"error": "objectKey is required", "requestId": rid})

    if not object_key.startswith(f"uploads/{sub}/"):
        return _resp(400, {"error": "Invalid objectKey (must be under your uploads/)", "requestId": rid})

    try:
        head = s3.head_object(Bucket=BUCKET, Key=object_key)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return _resp(404, {"error": "Object not found", "requestId": rid})
        _log("error", "head_object_failed", requestId=rid, detail=str(e))
        return _resp(500, {"error": "Failed to read object", "requestId": rid})

    size = int(head.get("ContentLength", 0) or 0)
    content_type = (head.get("ContentType") or "").lower()

    if size <= 0:
        try:
            s3.delete_object(Bucket=BUCKET, Key=object_key)
        except Exception:
            pass
        return _resp(400, {"error": "Empty upload", "requestId": rid})

    if size > MAX_BYTES:
        try:
            s3.delete_object(Bucket=BUCKET, Key=object_key)
        except Exception:
            pass
        return _resp(400, {"error": "File too large", "maxBytes": MAX_BYTES, "requestId": rid})

    if content_type not in ALLOWED_CONTENT_TYPES:
        try:
            s3.delete_object(Bucket=BUCKET, Key=object_key)
        except Exception:
            pass
        return _resp(400, {"error": "Unsupported content type", "allowed": sorted(ALLOWED_CONTENT_TYPES), "requestId": rid})

    filename = object_key.split("/", 2)[2]  # uploads/<sub>/<filename>
    final_key = f"photos/{sub}/{filename}"

    try:
        s3.copy_object(
            Bucket=BUCKET,
            Key=final_key,
            CopySource={"Bucket": BUCKET, "Key": object_key},
            ContentType=content_type,
            MetadataDirective="REPLACE",
        )
        s3.delete_object(Bucket=BUCKET, Key=object_key)
    except Exception as e:
        _log("error", "move_object_failed", requestId=rid, detail=str(e))
        return _resp(500, {"error": "Failed to move object", "requestId": rid})

    photo_id = str(uuid.uuid4())
    now = int(time.time())

    item = {
        "pk": f"USER#{sub}",
        "sk": f"PHOTO#{now}#{photo_id}",
        "photoId": photo_id,
        "userId": sub,
        "objectKey": final_key,
        "createdAt": now,
        "contentType": content_type,
        "sizeBytes": size,
    }

    table.put_item(Item=item)

    _log("info", "finalized", requestId=rid, sub=sub, photoId=photo_id, objectKey=final_key)
    return _resp(201, {"message": "finalized", "photoId": photo_id, "objectKey": final_key, "requestId": rid})