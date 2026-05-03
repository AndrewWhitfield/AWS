#!/bin/bash
set -e

ROLE_NAME="RecipeAppLambdaRole"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "Creating IAM Role: $ROLE_NAME"

# 1. Create the trust policy (allows Lambda to assume this role)
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 2. Create the role
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json

# 3. Create the permissions policy
cat > /tmp/permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAccess",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel"],
      "Resource": [
        "arn:aws:bedrock:${REGION}::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
        "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
        "arn:aws:bedrock:${REGION}:${ACCOUNT_ID}:inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0"
      ]
    },
    {
      "Sid": "DynamoDBAccess",
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:Query","dynamodb:Scan"],
      "Resource": "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/RecipeHistory"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
      "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:*"
    }
  ]
}
EOF

# 4. Attach the permissions policy
aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name RecipeAppPermissions \
  --policy-document file:///tmp/permissions-policy.json

echo "✅ IAM Role created: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"