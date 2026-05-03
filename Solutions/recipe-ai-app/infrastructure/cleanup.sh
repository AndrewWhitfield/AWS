#!/bin/bash

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="recipe-ai-app-${ACCOUNT_ID}"

echo "⚠️  This will delete all resources. Press Ctrl+C to cancel."
sleep 5

# Delete API Gateway
API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='RecipeAIAPI'].id" \
  --output text --region $REGION)
if [ -n "$API_ID" ]; then
  aws apigateway delete-rest-api --rest-api-id $API_ID --region $REGION
  echo "✅ API Gateway deleted"
fi

# Delete Lambda
aws lambda delete-function --function-name RecipeAIFunction --region $REGION

# Delete DynamoDB table
aws dynamodb delete-table --table-name RecipeHistory --region $REGION

# Delete IAM role & inline policy
aws iam delete-role-policy --role-name RecipeAppLambdaRole --policy-name RecipeAppPermissions
aws iam delete-role --role-name RecipeAppLambdaRole

# Empty and delete S3 bucket
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $BUCKET_NAME --region $REGION

echo "✅ Cleanup complete. Note: CloudFront distribution must be disabled then"
echo "   deleted manually via the AWS Console (takes ~15 min to disable)."