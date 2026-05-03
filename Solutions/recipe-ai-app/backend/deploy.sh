#!/bin/bash
set -e

FUNCTION_NAME="RecipeAIFunction"
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/RecipeAppLambdaRole"

echo "Packaging Lambda function..."

# Package into a zip file
zip -j function.zip lambda_function.py

# Check if function exists; update or create accordingly
if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION 2>/dev/null; then
  echo "Updating existing Lambda function..."
  aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://function.zip \
    --region $REGION
else
  echo "Creating new Lambda function..."
  aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --runtime python3.11 \
    --role $ROLE_ARN \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 30 \
    --memory-size 256 \
    --region $REGION
fi

# Clean up
rm function.zip

echo "✅ Lambda function '$FUNCTION_NAME' deployed successfully"