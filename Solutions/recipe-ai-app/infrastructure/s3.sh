#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$SCRIPT_DIR/../frontend"

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="recipe-ai-app-${ACCOUNT_ID}"

echo "Creating S3 bucket: $BUCKET_NAME"

# 1. Create the bucket
if [ "$REGION" == "us-east-1" ]; then
  aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION
else
  aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $REGION \
    --create-bucket-configuration LocationConstraint=$REGION
fi

# 2. Block all public access (CloudFront will serve the content)
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 3. Upload frontend files
echo "Uploading frontend files..."
aws s3 cp "$FRONTEND_DIR/index.html" s3://$BUCKET_NAME/index.html --content-type "text/html"
aws s3 cp "$FRONTEND_DIR/style.css"  s3://$BUCKET_NAME/style.css  --content-type "text/css"
aws s3 cp "$FRONTEND_DIR/app.js"     s3://$BUCKET_NAME/app.js     --content-type "application/javascript"

echo "✅ Files uploaded to S3 bucket: $BUCKET_NAME"

# 4. Create CloudFront Origin Access Control
echo "Creating CloudFront OAC..."
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    "Name=RecipeAppOAC,OriginAccessControlOriginType=s3,SigningBehavior=always,SigningProtocol=sigv4" \
  --query "OriginAccessControl.Id" --output text)

echo "OAC ID: $OAC_ID"

# 5. Create the CloudFront distribution
echo "Creating CloudFront distribution (this takes ~5 minutes)..."
DISTRIBUTION=$(aws cloudfront create-distribution --distribution-config "{
  \"CallerReference\": \"recipe-app-$(date +%s)\",
  \"Comment\": \"Recipe AI App\",
  \"DefaultRootObject\": \"index.html\",
  \"Origins\": {
    \"Quantity\": 1,
    \"Items\": [{
      \"Id\": \"S3Origin\",
      \"DomainName\": \"${BUCKET_NAME}.s3.${REGION}.amazonaws.com\",
      \"S3OriginConfig\": {\"OriginAccessIdentity\": \"\"},
      \"OriginAccessControlId\": \"${OAC_ID}\"
    }]
  },
  \"DefaultCacheBehavior\": {
    \"TargetOriginId\": \"S3Origin\",
    \"ViewerProtocolPolicy\": \"redirect-to-https\",
    \"CachePolicyId\": \"658327ea-f89d-4fab-a63d-7e88639e58f6\",
    \"Compress\": true,
    \"AllowedMethods\": {
      \"Quantity\": 2,
      \"Items\": [\"GET\", \"HEAD\"]
    }
  },
  \"Enabled\": true,
  \"HttpVersion\": \"http2\"
}")

DISTRIBUTION_ID=$(echo $DISTRIBUTION | python3 -c "import sys,json; print(json.load(sys.stdin)['Distribution']['Id'])")
CLOUDFRONT_URL=$(echo $DISTRIBUTION | python3 -c "import sys,json; print(json.load(sys.stdin)['Distribution']['DomainName'])")

echo "Distribution ID: $DISTRIBUTION_ID"

# 6. Update the bucket policy to allow CloudFront access
cat > /tmp/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFront",
    "Effect": "Allow",
    "Principal": {
      "Service": "cloudfront.amazonaws.com"
    },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
      }
    }
  }]
}
EOF

aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file:///tmp/bucket-policy.json

echo ""
echo "✅ CloudFront distribution created!"
echo "🌐 Your app URL (live in ~5 min): https://${CLOUDFRONT_URL}"
echo ""
echo "📌 Save this for reference:"
echo "   Bucket:          $BUCKET_NAME"
echo "   Distribution ID: $DISTRIBUTION_ID"
echo "   App URL:         https://${CLOUDFRONT_URL}"