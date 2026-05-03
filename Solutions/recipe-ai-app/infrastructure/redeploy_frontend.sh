#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/../frontend"

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="recipe-ai-app-${ACCOUNT_ID}"

echo "Redeploying frontend files..."
aws s3 cp "$FRONTEND_DIR/index.html" s3://$BUCKET_NAME/index.html --content-type "text/html"
aws s3 cp "$FRONTEND_DIR/style.css"  s3://$BUCKET_NAME/style.css  --content-type "text/css"
aws s3 cp "$FRONTEND_DIR/app.js"     s3://$BUCKET_NAME/app.js     --content-type "application/javascript"

# Invalidate CloudFront cache so changes go live immediately
DISTRIBUTION_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='Recipe AI App'].Id" \
  --output text)

if [ ! -z "$DISTRIBUTION_ID" ]; then
  aws cloudfront create-invalidation \
    --distribution-id $DISTRIBUTION_ID \
    --paths "/*"
  echo "✅ CloudFront cache invalidated"
fi

echo "✅ Frontend redeployed successfully"