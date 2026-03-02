import os
import json
import uuid
import time
import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
DEFAULT_CONTENT_TYPE = "image/jpeg"
MAX_BYTES = 5 * 1024 * 1024  # 5MB


def _ext_from_content_type(content_type: str) -> str:
    ct = (content_type or "").lower()
    if ct == "image/png":
        return "png"
    if ct == "image/webp":
        return "webp"
    return "jpg"


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

    qs = event.get("queryStringParameters") or {}
    content_type = (qs.get("contentType") or DEFAULT_CONTENT_TYPE).lower()

    raw_len = qs.get("contentLength")
    try:
        content_length = int(raw_len) if raw_len is not None else None
    except ValueError:
        content_length = None

    if content_length is None:
        return _resp(400, {"error": "contentLength is required", "requestId": rid})
    if content_length <= 0:
        return _resp(400, {"error": "contentLength must be > 0", "requestId": rid})
    if content_length > MAX_BYTES:
        return _resp(400, {"error": "File too large", "maxBytes": MAX_BYTES, "requestId": rid})

    if content_type not in ALLOWED_CONTENT_TYPES:
        return _resp(400, {"error": "Unsupported content type", "allowed": sorted(ALLOWED_CONTENT_TYPES), "requestId": rid})

    ext = _ext_from_content_type(content_type)
    object_key = f"uploads/{sub}/{uuid.uuid4()}.{ext}"

    upload_url = s3.generate_presigned_url(
        ClientMethod="put_object",
        Params={"Bucket": BUCKET, "Key": object_key, "ContentType": content_type},
        ExpiresIn=900,
    )

    _log("info", "presigned_url_issued", requestId=rid, sub=sub, objectKey=object_key)

    return _resp(200, {
        "uploadUrl": upload_url,
        "objectKey": object_key,
        "expiresInSeconds": 900,
        "maxBytes": MAX_BYTES,
        "contentType": content_type,
        "requestId": rid
    })