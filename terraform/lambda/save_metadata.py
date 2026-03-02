import json
import os
import time
import uuid
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])

def handler(event, context):
    body = event.get("body") or "{}"
    data = json.loads(body)

    object_key = data.get("objectKey")
    user_id = data.get("userId", "public-user")

    # --- Demo validation guardrails ---
    if user_id != "public-user":
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": "Invalid userId for demo"})
        }

    # objectKey must exist and be a string
    if not object_key or not isinstance(object_key, str):
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": "objectKey is required"})
        }

    # must be in uploads/ only
    if not object_key.startswith("uploads/"):
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": "Invalid objectKey"})
        }

    photo_id = str(uuid.uuid4())
    now = int(time.time())

    item = {
        "pk": f"USER#{user_id}",
        "sk": f"PHOTO#{now}#{photo_id}",
        "photoId": photo_id,
        "userId": user_id,
        "objectKey": object_key,
        "createdAt": now
    }

    table.put_item(Item=item)

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps({"message": "saved", "photoId": photo_id, "objectKey": object_key})
    }