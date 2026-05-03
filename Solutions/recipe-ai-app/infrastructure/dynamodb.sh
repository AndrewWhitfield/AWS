#!/bin/bash
set -e

REGION=$(aws configure get region)
TABLE_NAME="RecipeHistory"

echo "Creating DynamoDB table: $TABLE_NAME"

aws dynamodb create-table \
  --table-name $TABLE_NAME \
  --attribute-definitions \
      AttributeName=userId,AttributeType=S \
      AttributeName=timestamp,AttributeType=S \
  --key-schema \
      AttributeName=userId,KeyType=HASH \
      AttributeName=timestamp,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --region $REGION

# Wait until the table is active
echo "Waiting for table to become active..."
aws dynamodb wait table-exists --table-name $TABLE_NAME --region $REGION

echo "✅ DynamoDB table '$TABLE_NAME' is ready"