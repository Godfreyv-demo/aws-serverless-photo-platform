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

PRESERVE_DDB_ON_S3_FAIL = False  # keep strict consistency by default


def _req_id(event) -> str:
    return (event.get("requestContext") or {}).get("requestId") or str(uuid.uuid4())


def _user_sub(event):
    claims = (((event.get("requestContext") or {}).get("authorizer") or {}).get("jwt") or {}).get("claims") or {}
    return claims.get("sub")


def _cors_headers():
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
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

    # Expect DELETE /photos with JSON body: {"sk":"PHOTO#...#..."}
    body_raw = event.get("body") or "{}"
    try:
        data = json.loads(body_raw)
    except Exception:
        return _resp(400, {"error": "Invalid JSON body", "requestId": rid})

    sk = data.get("sk")
    if not sk or not isinstance(sk, str):
        return _resp(400, {"error": "sk is required", "requestId": rid})

    pk = f"USER#{sub}"

    # 1) Get item (authoritative source for objectKey)
    try:
        get_resp = table.get_item(Key={"pk": pk, "sk": sk})
    except Exception as e:
        return _resp(500, {"error": "DynamoDB get_item failed", "detail": str(e), "requestId": rid})

    item = get_resp.get("Item")
    if not item:
        return _resp(404, {"error": "Photo not found", "requestId": rid})

    object_key = item.get("objectKey") or ""
    # Must be under photos/<sub>/...
    if not object_key.startswith(f"photos/{sub}/"):
        # This should never happen unless data is corrupted/tampered
        return _resp(403, {"error": "Forbidden", "requestId": rid})

    # 2) Delete from S3 first (so DDB doesn't reference missing object if delete fails later)
    try:
        s3.delete_object(Bucket=BUCKET, Key=object_key)
    except Exception as e:
        if PRESERVE_DDB_ON_S3_FAIL:
            return _resp(500, {"error": "Failed to delete S3 object", "detail": str(e), "requestId": rid})
        # If you ever flip this, you’d delete DDB anyway and accept possible orphaned S3 objects
        return _resp(500, {"error": "Failed to delete S3 object", "detail": str(e), "requestId": rid})

    # 3) Delete from DynamoDB (use conditional to avoid accidental wrong user/item)
    try:
        table.delete_item(
            Key={"pk": pk, "sk": sk},
            ConditionExpression="attribute_exists(pk) AND attribute_exists(sk)",
        )
    except ClientError as e:
        # If DDB delete fails after S3 delete, you're in an inconsistent state.
        # This is rare; you can re-run delete safely.
        return _resp(500, {"error": "Failed to delete metadata", "detail": str(e), "requestId": rid})
    except Exception as e:
        return _resp(500, {"error": "Failed to delete metadata", "detail": str(e), "requestId": rid})

    return _resp(200, {"message": "deleted", "sk": sk, "objectKey": object_key, "requestId": rid})