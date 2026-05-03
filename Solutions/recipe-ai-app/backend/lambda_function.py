import json
import boto3
import uuid
import logging
from datetime import datetime, timezone

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
bedrock = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("RecipeHistory")

MODEL_ID = "us.anthropic.claude-haiku-4-5-20251001-v1:0"

# CORS headers — update the origin when you have your CloudFront URL
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
}


def build_prompt(ingredients: list[str]) -> str:
    """Build a structured prompt for the AI model."""
    ingredients_str = ", ".join(ingredients)
    return f"""You are a helpful chef assistant. A user has the following ingredients available:

{ingredients_str}

Please suggest 2 simple recipes they can make. For each recipe provide:
1. Recipe name
2. Additional ingredients needed (if any)
3. Step-by-step cooking instructions (keep it concise)
4. Approximate cooking time

Format your response clearly with each recipe separated by a divider line (---).
Keep instructions beginner-friendly."""


def invoke_bedrock(prompt: str) -> str:
    """Call Amazon Bedrock Claude 3 Haiku and return the response text."""
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "messages": [
            {
                "role": "user",
                "content": prompt
            }
        ]
    }

    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(body),
        contentType="application/json",
        accept="application/json"
    )

    response_body = json.loads(response["body"].read())
    return response_body["content"][0]["text"]


def save_to_dynamodb(user_id: str, ingredients: list[str], recipe: str) -> str:
    """Persist the query and result to DynamoDB."""
    timestamp = datetime.now(timezone.utc).isoformat()
    record_id = str(uuid.uuid4())

    table.put_item(Item={
        "userId": user_id,
        "timestamp": timestamp,
        "recordId": record_id,
        "ingredients": ingredients,
        "recipe": recipe
    })

    return record_id


def get_history(user_id: str) -> list:
    """Retrieve the last 10 recipe searches for a user."""
    response = table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("userId").eq(user_id),
        ScanIndexForward=False,  # newest first
        Limit=10
    )
    return response.get("Items", [])


def lambda_handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    http_method = event.get("httpMethod", "")
    path = event.get("path", "")

    # Handle CORS preflight
    if http_method == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    # POST /recipes — Generate a recipe
    if http_method == "POST" and path == "/recipes":
        try:
            body = json.loads(event.get("body", "{}"))
            ingredients = body.get("ingredients", [])
            user_id = body.get("userId", "anonymous")

            # Validate input
            if not ingredients or not isinstance(ingredients, list):
                return {
                    "statusCode": 400,
                    "headers": CORS_HEADERS,
                    "body": json.dumps({"error": "Please provide a list of ingredients."})
                }

            if len(ingredients) > 20:
                return {
                    "statusCode": 400,
                    "headers": CORS_HEADERS,
                    "body": json.dumps({"error": "Please provide no more than 20 ingredients."})
                }

            # Sanitise ingredients
            clean_ingredients = [str(i).strip()[:50] for i in ingredients if str(i).strip()]

            # Build prompt and call Bedrock
            prompt = build_prompt(clean_ingredients)
            logger.info("Calling Bedrock for user: %s", user_id)
            recipe_text = invoke_bedrock(prompt)

            # Save to DynamoDB
            record_id = save_to_dynamodb(user_id, clean_ingredients, recipe_text)

            return {
                "statusCode": 200,
                "headers": CORS_HEADERS,
                "body": json.dumps({
                    "recordId": record_id,
                    "ingredients": clean_ingredients,
                    "recipe": recipe_text
                })
            }

        except Exception as e:
            logger.error("Error generating recipe: %s", str(e))
            return {
                "statusCode": 500,
                "headers": CORS_HEADERS,
                "body": json.dumps({"error": "Failed to generate recipe. Please try again."})
            }

    # GET /history?userId=xxx — Retrieve search history
    if http_method == "GET" and path == "/history":
        try:
            query_params = event.get("queryStringParameters") or {}
            user_id = query_params.get("userId", "anonymous")

            history = get_history(user_id)

            return {
                "statusCode": 200,
                "headers": CORS_HEADERS,
                "body": json.dumps({"history": history})
            }

        except Exception as e:
            logger.error("Error fetching history: %s", str(e))
            return {
                "statusCode": 500,
                "headers": CORS_HEADERS,
                "body": json.dumps({"error": "Failed to retrieve history."})
            }

    # Fallback
    return {
        "statusCode": 404,
        "headers": CORS_HEADERS,
        "body": json.dumps({"error": "Route not found."})
    }