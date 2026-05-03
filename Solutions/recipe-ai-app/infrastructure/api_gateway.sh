#!/bin/bash
set -e

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
FUNCTION_NAME="RecipeAIFunction"
API_NAME="RecipeAIAPI"

echo "Creating API Gateway: $API_NAME"

# 1. Create REST API
API_ID=$(aws apigateway create-rest-api \
  --name $API_NAME \
  --description "Recipe AI App REST API" \
  --region $REGION \
  --query "id" --output text)

echo "API ID: $API_ID"

# 2. Get the root resource ID
ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --region $REGION \
  --query "items[0].id" --output text)

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

# Helper: create a child resource
create_resource() {
  local PARENT_ID=$1
  local PATH_PART=$2

  local RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $PARENT_ID \
    --path-part $PATH_PART \
    --region $REGION \
    --query "id" --output text)

  echo $RESOURCE_ID
}

# Helper: attach a method with Lambda proxy integration
setup_method() {
  local RESOURCE_ID=$1
  local METHOD=$2

  aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method $METHOD \
    --authorization-type NONE \
    --region $REGION

  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method $METHOD \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --region $REGION
}

# Helper: add OPTIONS method for CORS preflight
setup_options() {
  local RESOURCE_ID=$1

  # OPTIONS method
  aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type NONE \
    --region $REGION

  # MOCK integration
  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json": "{\"statusCode\": 200}"}' \
    --region $REGION

  # Method response
  aws apigateway put-method-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters "{
      \"method.response.header.Access-Control-Allow-Headers\": false,
      \"method.response.header.Access-Control-Allow-Methods\": false,
      \"method.response.header.Access-Control-Allow-Origin\": false
    }" \
    --region $REGION

  # Integration response — static values MUST be wrapped in single quotes
  aws apigateway put-integration-response \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters "{
      \"method.response.header.Access-Control-Allow-Headers\": \"'Content-Type,X-Amz-Date,Authorization,X-Api-Key'\",
      \"method.response.header.Access-Control-Allow-Methods\": \"'GET,POST,OPTIONS'\",
      \"method.response.header.Access-Control-Allow-Origin\": \"'*'\"
    }" \
    --region $REGION
}

# 3. Create /recipes (POST)
echo "Creating /recipes endpoint..."
RECIPES_ID=$(create_resource $ROOT_ID "recipes")
setup_method $RECIPES_ID POST
setup_options $RECIPES_ID

# 4. Create /history (GET)
echo "Creating /history endpoint..."
HISTORY_ID=$(create_resource $ROOT_ID "history")
setup_method $HISTORY_ID GET
setup_options $HISTORY_ID

# 5. Grant API Gateway permission to invoke Lambda
aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
  --region $REGION 2>/dev/null || echo "Permission already exists, skipping."

# 6. Deploy to prod stage
echo "Deploying API to 'prod' stage..."
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --region $REGION

API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod"

echo ""
echo "✅ API Gateway deployed!"
echo "📌 Your API URL:"
echo "   $API_URL"
echo ""

echo $API_URL > frontend/api-url.txt
