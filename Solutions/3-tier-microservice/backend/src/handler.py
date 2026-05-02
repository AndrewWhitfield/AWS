import json
import os
import uuid
import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])
ALLOWED_ORIGIN = os.environ["ALLOWED_ORIGIN"]


def cors_headers():
    return {
        "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
        "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
        "Content-Type": "application/json",
    }


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": cors_headers(),
        "body": json.dumps(body),
    }


def get_items():
    result = table.query(
        KeyConditionExpression=Key("pk").eq("ITEM")
    )
    return response(200, result.get("Items", []))


def get_item(item_id):
    result = table.get_item(Key={"pk": "ITEM", "sk": item_id})
    item = result.get("Item")
    if not item:
        return response(404, {"error": "Item not found"})
    return response(200, item)


def create_item(body):
    if not body:
        return response(400, {"error": "Request body is required"})
    data = json.loads(body)
    item_id = str(uuid.uuid4())
    item = {
        "pk": "ITEM",
        "sk": item_id,
        "id": item_id,
        **data,
    }
    table.put_item(Item=item)
    return response(201, item)


def delete_item(item_id):
    table.delete_item(Key={"pk": "ITEM", "sk": item_id})
    return response(200, {"message": f"Item {item_id} deleted"})


def lambda_handler(event, context):
    method = event.get("httpMethod", "")
    path_params = event.get("pathParameters") or {}
    item_id = path_params.get("id")
    body = event.get("body")

    # Handle CORS preflight
    if method == "OPTIONS":
        return response(200, {})

    if method == "GET" and not item_id:
        return get_items()
    elif method == "GET" and item_id:
        return get_item(item_id)
    elif method == "POST":
        return create_item(body)
    elif method == "DELETE" and item_id:
        return delete_item(item_id)

    return response(405, {"error": "Method not allowed"})