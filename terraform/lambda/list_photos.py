import json
import os
import time
import uuid
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

BUCKET = os.environ["BUCKET_NAME"]
table = dynamodb.Table(os.environ["TABLE_NAME"])

DEFAULT_LIMIT = 25
MAX_LIMIT = 100
PRESIGN_SECONDS = 900


def _req_id(event) -> str:
    return (event.get("requestContext") or {}).get("requestId") or str(uuid.uuid4())


def _user_sub(event):
    claims = (((event.get("requestContext") or {}).get("authorizer") or {}).get("jwt") or {}).get("claims") or {}
    return claims.get("sub")


def _json_safe(obj):
    if isinstance(obj, list):
        return [_json_safe(i) for i in obj]
    if isinstance(obj, dict):
        return {k: _json_safe(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        return int(obj) if obj % 1 == 0 else float(obj)
    return obj


def _cors_headers():
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        "Access-Control-Allow-Headers": "content-type,authorization",
    }


def _resp(status: int, body: dict):
    return {"statusCode": status, "headers": _cors_headers(), "body": json.dumps(_json_safe(body))}


def handler(event, context):
    rid = _req_id(event)

    method = (event.get("requestContext") or {}).get("http", {}).get("method", "")
    if method == "OPTIONS":
        return _resp(200, {"ok": True})

    sub = _user_sub(event)
    if not sub:
        return _resp(401, {"error": "Unauthorized", "requestId": rid})

    qs = event.get("queryStringParameters") or {}
    limit_raw = qs.get("limit")
    try:
        limit = int(limit_raw) if limit_raw else DEFAULT_LIMIT
    except ValueError:
        limit = DEFAULT_LIMIT
    limit = max(1, min(limit, MAX_LIMIT))

    resp = table.query(
        KeyConditionExpression=Key("pk").eq(f"USER#{sub}"),
        ScanIndexForward=False,
        Limit=limit,
    )

    items = _json_safe(resp.get("Items", []) or [])

    for item in items:
        key = item.get("objectKey")
        if not key:
            continue
        item["viewUrl"] = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": BUCKET, "Key": key},
            ExpiresIn=PRESIGN_SECONDS,
        )

    return _resp(200, {"items": items, "expiresInSeconds": PRESIGN_SECONDS, "requestId": rid})