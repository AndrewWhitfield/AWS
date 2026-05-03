# 🍳 AI Recipe Suggester — Complete Implementation Guide

---

## 📋 Table of Contents
1. [Prerequisites](#1-prerequisites)
2. [Project Setup](#2-project-setup)
3. [IAM Role & Permissions](#3-iam-role--permissions)
4. [DynamoDB Table](#4-dynamodb-table)
5. [Lambda Function](#5-lambda-function)
6. [API Gateway](#6-api-gateway)
7. [Frontend Files](#7-frontend-files)
8. [S3 & CloudFront](#8-s3--cloudfront)
9. [Testing](#9-testing)
10. [Troubleshooting](#10-troubleshooting)
11. [Cleanup](#11-cleanup)

---

## 1. Prerequisites

### Install the AWS CLI

**macOS (Homebrew)**
```bash
brew install awscli
```

**macOS / Linux (Manual)**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Verify installation**
```bash
aws --version
# Expected: aws-cli/2.x.x Python/3.x.x
```

---

### Create AWS Access Keys

1. Open the [AWS Console](https://console.aws.amazon.com)
2. Navigate to **IAM** → **Users** → select your user
3. Click **Security credentials** → **Create access key**
4. Select **Command Line Interface (CLI)** → confirm
5. Copy your **Access Key ID** and **Secret Access Key**

---

### Configure the AWS CLI

Run the following and enter all four values when prompted:

```bash
aws configure
```

```
AWS Access Key ID [None]:      ← your Access Key ID
AWS Secret Access Key [None]:  ← your Secret Access Key
Default region name [None]:    us-east-1
Default output format [None]:  json
```

**Verify all four values are set — none should say `None`:**
```bash
aws configure list
```

Expected output:
```
      Name                    Value             Type    Location
      ----                    -----             ----    --------
access_key     ****************XXXX              env
secret_key     ****************XXXX              env
    region                us-east-1      config-file    ~/.aws/config
output                         json      config-file    ~/.aws/config
```

---

### Attach AWS Marketplace Permissions

This is required to activate Anthropic models on Bedrock:

```bash
IAM_USER=$(aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)

aws iam attach-user-policy \
  --user-name $IAM_USER \
  --policy-arn arn:aws:iam::aws:policy/AWSMarketplaceFullAccess

echo "✅ Marketplace permissions attached"
```

---

### Verify Amazon Bedrock Access

Test that Claude Haiku 4.5 is accessible in your account:

```bash
cat > /tmp/bedrock-request.json << 'EOF'
{
  "anthropic_version": "bedrock-2023-05-31",
  "max_tokens": 100,
  "messages": [{ "role": "user", "content": "Say hello" }]
}
EOF

aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-haiku-4-5-20251001-v1:0 \
  --body fileb:///tmp/bedrock-request.json \
  --content-type "application/json" \
  --accept "application/json" \
  /tmp/bedrock-test.json && cat /tmp/bedrock-test.json
```

**Expected output:**
```json
{
    "id": "msg_01XxXx",
    "type": "message",
    "role": "assistant",
    "content": [{ "type": "text", "text": "Hello! How can I help you today?" }],
    "model": "claude-haiku-4-5-20251001",
    "stop_reason": "end_turn"
}
```

> ⚠️ If this fails, see [Section 10 — Troubleshooting](#10-troubleshooting) before continuing.

---

## 2. Project Setup

### Create the Project Structure

```bash
mkdir -p recipe-ai-app/{infrastructure,backend,frontend}
cd recipe-ai-app
```

**Verify the structure:**
```bash
ls
# Expected: infrastructure/  backend/  frontend/
```

> ⚠️ All commands from this point forward must be run from inside the
> `recipe-ai-app/` folder. Run `pwd` at any time to confirm your location.

---

## 3. IAM Role & Permissions

Create the IAM role that grants the Lambda function access to Bedrock,
DynamoDB, and CloudWatch.

```bash
cat > infrastructure/iam.sh << 'SCRIPT'
#!/bin/bash
set -e

ROLE_NAME="RecipeAppLambdaRole"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

echo "Creating IAM Role: $ROLE_NAME"

cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "lambda.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json

cat > /tmp/permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockAccess",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel"],
      "Resource": "arn:aws:bedrock:${REGION}::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0"
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

aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name RecipeAppPermissions \
  --policy-document file:///tmp/permissions-policy.json

echo "✅ IAM Role created: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
SCRIPT

chmod +x infrastructure/iam.sh
./infrastructure/iam.sh
```

**Expected output:**
```
Creating IAM Role: RecipeAppLambdaRole
✅ IAM Role created: arn:aws:iam::123456789012:role/RecipeAppLambdaRole
```

**Verify:**
```bash
aws iam get-role --role-name RecipeAppLambdaRole \
  --query "Role.Arn" --output text
```

---

## 4. DynamoDB Table

Creates the table that stores recipe search history.

```bash
cat > infrastructure/dynamodb.sh << 'SCRIPT'
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

echo "Waiting for table to become active..."
aws dynamodb wait table-exists --table-name $TABLE_NAME --region $REGION

echo "✅ DynamoDB table '$TABLE_NAME' is ready"
SCRIPT

chmod +x infrastructure/dynamodb.sh
./infrastructure/dynamodb.sh
```

**Expected output:**
```
Creating DynamoDB table: RecipeHistory
Waiting for table to become active...
✅ DynamoDB table 'RecipeHistory' is ready
```

**Verify:**
```bash
aws dynamodb describe-table \
  --table-name RecipeHistory \
  --query "Table.TableStatus" --output text
# Expected: ACTIVE
```

---

## 5. Lambda Function

### Create the Function Code

```bash
cat > backend/lambda_function.py << 'EOF'
import json
import boto3
import uuid
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client("bedrock-runtime")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("RecipeHistory")

MODEL_ID = "anthropic.claude-haiku-4-5-20251001-v1:0"

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
}


def build_prompt(ingredients):
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


def invoke_bedrock(prompt):
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}]
    }
    response = bedrock.invoke_model(
        modelId=MODEL_ID,
        body=json.dumps(body),
        contentType="application/json",
        accept="application/json"
    )
    response_body = json.loads(response["body"].read())
    return response_body["content"][0]["text"]


def save_to_dynamodb(user_id, ingredients, recipe):
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


def get_history(user_id):
    response = table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key("userId").eq(user_id),
        ScanIndexForward=False,
        Limit=10
    )
    return response.get("Items", [])


def lambda_handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    http_method = event.get("httpMethod", "")
    path = event.get("path", "")

    if http_method == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    if http_method == "POST" and path == "/recipes":
        try:
            body = json.loads(event.get("body", "{}"))
            ingredients = body.get("ingredients", [])
            user_id = body.get("userId", "anonymous")

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

            clean_ingredients = [str(i).strip()[:50] for i in ingredients if str(i).strip()]
            prompt = build_prompt(clean_ingredients)
            logger.info("Calling Bedrock for user: %s", user_id)
            recipe_text = invoke_bedrock(prompt)
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

    return {
        "statusCode": 404,
        "headers": CORS_HEADERS,
        "body": json.dumps({"error": "Route not found."})
    }
EOF
```

### Create the Deploy Script

```bash
cat > backend/deploy.sh << 'SCRIPT'
#!/bin/bash
set -e

FUNCTION_NAME="RecipeAIFunction"
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/RecipeAppLambdaRole"

echo "Packaging Lambda function..."
zip -j function.zip lambda_function.py

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

rm function.zip
echo "✅ Lambda function '$FUNCTION_NAME' deployed successfully"
SCRIPT

chmod +x backend/deploy.sh
cd backend && ./deploy.sh && cd ..
```

**Expected output:**
```
Packaging Lambda function...
Creating new Lambda function...
✅ Lambda function 'RecipeAIFunction' deployed successfully
```

---

## 6. API Gateway

```bash
cat > infrastructure/api_gateway.sh << 'SCRIPT'
#!/bin/bash
set -e

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
FUNCTION_NAME="RecipeAIFunction"
API_NAME="RecipeAIAPI"

echo "Creating API Gateway: $API_NAME"

API_ID=$(aws apigateway create-rest-api \
  --name $API_NAME \
  --description "Recipe AI App REST API" \
  --region $REGION \
  --query "id" --output text)

echo "API ID: $API_ID"

ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --region $REGION \
  --query "items[0].id" --output text)

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}"

create_resource() {
  local PARENT_ID=$1
  local PATH_PART=$2
  aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $PARENT_ID \
    --path-part $PATH_PART \
    --region $REGION \
    --query "id" --output text
}

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

setup_options() {
  local RESOURCE_ID=$1

  aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type NONE \
    --region $REGION

  aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json": "{\"statusCode\": 200}"}' \
    --region $REGION

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

echo "Creating /recipes endpoint..."
RECIPES_ID=$(create_resource $ROOT_ID "recipes")
setup_method $RECIPES_ID POST
setup_options $RECIPES_ID

echo "Creating /history endpoint..."
HISTORY_ID=$(create_resource $ROOT_ID "history")
setup_method $HISTORY_ID GET
setup_options $HISTORY_ID

aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id apigateway-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*" \
  --region $REGION 2>/dev/null || echo "Permission already exists, skipping."

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

echo $API_URL > ../frontend/api_url.txt
SCRIPT

chmod +x infrastructure/api_gateway.sh
./infrastructure/api_gateway.sh
```

**Expected output:**
```
Creating API Gateway: RecipeAIAPI
API ID: abc123xyz
Creating /recipes endpoint...
Creating /history endpoint...
Deploying API to 'prod' stage...

✅ API Gateway deployed!
📌 Your API URL:
   https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod
```

> 📌 The API URL is automatically saved to `frontend/api_url.txt`

---

## 7. Frontend Files

### Create `index.html`

```bash
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>🍳 AI Recipe Suggester</title>
  <link rel="stylesheet" href="style.css" />
</head>
<body>
  <div class="container">
    <header>
      <h1>🍳 AI Recipe Suggester</h1>
      <p>Enter the ingredients you have, and let AI suggest recipes for you!</p>
    </header>
    <main>
      <section class="card" id="input-section">
        <h2>Your Ingredients</h2>
        <div class="ingredient-input-row">
          <input type="text" id="ingredient-input" placeholder="e.g. chicken, garlic, lemon..." maxlength="50"/>
          <button id="add-btn" onclick="addIngredient()">Add</button>
        </div>
        <div id="ingredient-tags" class="tags-container"></div>
        <button id="suggest-btn" onclick="getSuggestions()" disabled>✨ Suggest Recipes</button>
      </section>
      <section class="card hidden" id="loading-section">
        <div class="loader"></div>
        <p>Our AI chef is thinking...</p>
      </section>
      <section class="card hidden" id="results-section">
        <h2>🍽️ Recipe Suggestions</h2>
        <div id="recipe-output"></div>
        <button onclick="resetForm()" class="secondary-btn">🔄 Try Different Ingredients</button>
      </section>
      <section class="card" id="history-section">
        <div class="history-header">
          <h2>📜 Recent Searches</h2>
          <button onclick="loadHistory()" class="small-btn">Refresh</button>
        </div>
        <div id="history-list">
          <p class="empty-state">No history yet. Generate your first recipe!</p>
        </div>
      </section>
    </main>
  </div>
  <script src="app.js"></script>
</body>
</html>
EOF
```

### Create `style.css`

```bash
cat > frontend/style.css << 'EOF'
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', system-ui, sans-serif; background: #f0f4f8; color: #2d3748; min-height: 100vh; padding: 2rem 1rem; }
.container { max-width: 760px; margin: 0 auto; }
header { text-align: center; margin-bottom: 2rem; }
header h1 { font-size: 2.2rem; color: #2b6cb0; margin-bottom: 0.5rem; }
header p { color: #718096; font-size: 1rem; }
.card { background: white; border-radius: 12px; padding: 1.75rem; margin-bottom: 1.5rem; box-shadow: 0 2px 8px rgba(0,0,0,0.07); }
.card h2 { font-size: 1.2rem; margin-bottom: 1rem; color: #2d3748; }
.ingredient-input-row { display: flex; gap: 0.5rem; margin-bottom: 1rem; }
input[type="text"] { flex: 1; padding: 0.65rem 1rem; border: 1.5px solid #e2e8f0; border-radius: 8px; font-size: 1rem; outline: none; transition: border-color 0.2s; }
input[type="text"]:focus { border-color: #4299e1; }
.tags-container { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; min-height: 2rem; }
.tag { display: flex; align-items: center; gap: 0.4rem; background: #ebf8ff; color: #2b6cb0; border: 1px solid #bee3f8; border-radius: 20px; padding: 0.3rem 0.75rem; font-size: 0.9rem; }
.tag button { background: none; border: none; cursor: pointer; color: #63b3ed; font-size: 1rem; line-height: 1; padding: 0; }
.tag button:hover { color: #e53e3e; }
button { cursor: pointer; border: none; border-radius: 8px; font-size: 1rem; font-weight: 500; padding: 0.65rem 1.25rem; transition: background 0.2s, transform 0.1s; }
button:active { transform: scale(0.98); }
#add-btn { background: #4299e1; color: white; white-space: nowrap; }
#add-btn:hover { background: #3182ce; }
#suggest-btn { width: 100%; padding: 0.85rem; background: #48bb78; color: white; font-size: 1.1rem; }
#suggest-btn:hover:not(:disabled) { background: #38a169; }
#suggest-btn:disabled { background: #a0aec0; cursor: not-allowed; }
.secondary-btn { background: #edf2f7; color: #4a5568; margin-top: 1.25rem; width: 100%; }
.secondary-btn:hover { background: #e2e8f0; }
.small-btn { background: #edf2f7; color: #4a5568; font-size: 0.85rem; padding: 0.35rem 0.75rem; }
#loading-section { text-align: center; padding: 2.5rem; }
.loader { width: 44px; height: 44px; border: 4px solid #e2e8f0; border-top-color: #4299e1; border-radius: 50%; animation: spin 0.9s linear infinite; margin: 0 auto 1rem; }
@keyframes spin { to { transform: rotate(360deg); } }
#recipe-output { white-space: pre-wrap; line-height: 1.75; color: #2d3748; background: #f7fafc; border-radius: 8px; padding: 1.25rem; border: 1px solid #e2e8f0; font-size: 0.97rem; }
.history-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; }
.history-item { border: 1px solid #e2e8f0; border-radius: 8px; padding: 0.85rem 1rem; margin-bottom: 0.75rem; cursor: pointer; transition: background 0.15s; }
.history-item:hover { background: #f7fafc; }
.history-item .date { font-size: 0.8rem; color: #a0aec0; margin-bottom: 0.3rem; }
.history-item .ingredients { font-weight: 500; font-size: 0.95rem; color: #2b6cb0; }
.empty-state { color: #a0aec0; font-style: italic; }
.hidden { display: none !important; }
@media (max-width: 480px) { header h1 { font-size: 1.7rem; } .ingredient-input-row { flex-direction: column; } #add-btn { width: 100%; } }
EOF
```

### Create `app.js`

```bash
# Reads the API URL saved automatically by api_gateway.sh
API_URL=$(cat frontend/api_url.txt)

cat > frontend/app.js << EOF
const API_BASE_URL = "${API_URL}";

const USER_ID = (() => {
  let id = localStorage.getItem("recipeUserId");
  if (!id) { id = "user_" + Math.random().toString(36).substring(2, 11); localStorage.setItem("recipeUserId", id); }
  return id;
})();

let ingredients = [];

function addIngredient() {
  const input = document.getElementById("ingredient-input");
  const value = input.value.trim().toLowerCase();
  if (!value) return;
  if (ingredients.includes(value)) { showInputError("Ingredient already added."); return; }
  if (ingredients.length >= 20) { showInputError("Maximum 20 ingredients allowed."); return; }
  ingredients.push(value);
  input.value = "";
  input.focus();
  renderTags();
  updateSuggestButton();
}

function removeIngredient(index) {
  ingredients.splice(index, 1);
  renderTags();
  updateSuggestButton();
}

function renderTags() {
  const container = document.getElementById("ingredient-tags");
  container.innerHTML = ingredients.map((ing, i) =>
    \`<span class="tag">\${escapeHtml(ing)}<button onclick="removeIngredient(\${i})" title="Remove">✕</button></span>\`
  ).join("");
}

function updateSuggestButton() {
  document.getElementById("suggest-btn").disabled = ingredients.length === 0;
}

function showInputError(msg) {
  const input = document.getElementById("ingredient-input");
  input.setCustomValidity(msg);
  input.reportValidity();
  setTimeout(() => input.setCustomValidity(""), 2500);
}

document.getElementById("ingredient-input").addEventListener("keydown", (e) => {
  if (e.key === "Enter") addIngredient();
});

async function getSuggestions() {
  if (ingredients.length === 0) return;
  showSection("loading-section");
  hideSection("results-section");
  try {
    const response = await fetch(\`\${API_BASE_URL}/recipes\`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ingredients, userId: USER_ID }),
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Unknown error");
    displayRecipe(data.recipe);
    loadHistory();
  } catch (err) {
    console.error("Error:", err);
    displayError(err.message);
  } finally {
    hideSection("loading-section");
  }
}

function displayRecipe(recipeText) {
  document.getElementById("recipe-output").textContent = recipeText;
  showSection("results-section");
}

function displayError(message) {
  document.getElementById("recipe-output").innerHTML =
    \`<span style="color:#e53e3e">⚠️ Error: \${escapeHtml(message)}</span>\`;
  showSection("results-section");
}

async function loadHistory() {
  const container = document.getElementById("history-list");
  try {
    const response = await fetch(\`\${API_BASE_URL}/history?userId=\${encodeURIComponent(USER_ID)}\`);
    const data = await response.json();
    const history = data.history || [];
    if (history.length === 0) {
      container.innerHTML = '<p class="empty-state">No history yet. Generate your first recipe!</p>';
      return;
    }
    container.innerHTML = history.map((item) => {
      const date = new Date(item.timestamp).toLocaleString();
      const ings = (item.ingredients || []).join(", ");
      return \`<div class="history-item" onclick="showHistoryItem(this)" data-recipe="\${escapeHtml(item.recipe)}">
        <div class="date">🕐 \${date}</div>
        <div class="ingredients">🥗 \${escapeHtml(ings)}</div>
      </div>\`;
    }).join("");
  } catch (err) {
    container.innerHTML = '<p class="empty-state">Could not load history.</p>';
  }
}

function showHistoryItem(el) {
  displayRecipe(el.getAttribute("data-recipe"));
  document.getElementById("results-section").scrollIntoView({ behavior: "smooth" });
}

function resetForm() {
  ingredients = [];
  renderTags();
  updateSuggestButton();
  hideSection("results-section");
  document.getElementById("ingredient-input").focus();
}

function showSection(id) { document.getElementById(id).classList.remove("hidden"); }
function hideSection(id) { document.getElementById(id).classList.add("hidden"); }
function escapeHtml(str) {
  return String(str).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}

window.addEventListener("DOMContentLoaded", () => { loadHistory(); });
EOF
```

**Verify all three files exist:**
```bash
ls frontend/
# Expected: index.html  style.css  app.js  api_url.txt
```

---

## 8. S3 & CloudFront

```bash
cat > infrastructure/s3.sh << 'SCRIPT'
#!/bin/bash
set -e

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="recipe-ai-app-${ACCOUNT_ID}"

echo "Creating S3 bucket: $BUCKET_NAME"

if [ "$REGION" == "us-east-1" ]; then
  aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION
else
  aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $REGION \
    --create-bucket-configuration LocationConstraint=$REGION
fi

aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "Uploading frontend files..."
aws s3 cp ../frontend/index.html s3://$BUCKET_NAME/index.html --content-type "text/html"
aws s3 cp ../frontend/style.css  s3://$BUCKET_NAME/style.css  --content-type "text/css"
aws s3 cp ../frontend/app.js     s3://$BUCKET_NAME/app.js     --content-type "application/javascript"

echo "✅ Files uploaded to S3"

echo "Creating CloudFront OAC..."
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    "Name=RecipeAppOAC,OriginAccessControlOriginType=s3,SigningBehavior=always,SigningProtocol=sigv4" \
  --query "OriginAccessControl.Id" --output text)

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

cat > /tmp/bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFront",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
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
echo "Bucket:          $BUCKET_NAME"
echo "Distribution ID: $DISTRIBUTION_ID"
SCRIPT

chmod +x infrastructure/s3.sh
cd infrastructure && ./s3.sh && cd ..
```

**Expected output:**
```
Creating S3 bucket: recipe-ai-app-123456789012
Uploading frontend files...
✅ Files uploaded to S3
Creating CloudFront OAC...
Creating CloudFront distribution (this takes ~5 minutes)...

✅ CloudFront distribution created!
🌐 Your app URL (live in ~5 min): https://d1234abcd.cloudfront.net
```

> ⏳ Wait **3–5 minutes** before opening the URL — CloudFront needs time to
> propagate globally.

---

## 9. Testing

### Test Lambda Directly

```bash
aws lambda invoke \
  --function-name RecipeAIFunction \
  --payload '{"httpMethod":"POST","path":"/recipes","body":"{\"ingredients\":[\"egg\",\"butter\"],\"userId\":\"test\"}"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda_response.json && cat /tmp/lambda_response.json | python3 -m json.tool
```

**Expected output:**
```json
{
    "statusCode": 200,
    "body": "{\"recordId\": \"...\", \"ingredients\": [\"egg\", \"butter\"], \"recipe\": \"...\"}"
}
```

---

### Test via API Gateway

```bash
API_URL=$(cat frontend/api_url.txt)

# Test recipe generation
curl -X POST "$API_URL/recipes" \
  -H "Content-Type: application/json" \
  -d '{"ingredients":["pasta","tomato","basil"],"userId":"test"}' \
  | python3 -m json.tool

# Test history
curl "$API_URL/history?userId=test" | python3 -m json.tool
```

---

### Test the Frontend

1. Open your CloudFront URL (e.g. `https://d1234abcd.cloudfront.net`)
2. Type an ingredient → press **Enter** or click **Add**
3. Add 2–3 more ingredients
4. Click **✨ Suggest Recipes**
5. Confirm a recipe appears within ~5 seconds
6. Confirm **Recent Searches** updates automatically

---

## 10. Troubleshooting

### ❌ `Unknown output type: None`
The AWS CLI region or output format is not configured:
```bash
aws configure set region us-east-1
aws configure set output json
```

---

### ❌ `infrastructure/iam.sh: No such file or directory`
You are not in the correct directory, or the files have not been created yet:
```bash
# Check your location
pwd
# Should end with: /recipe-ai-app

# If not, navigate there
cd recipe-ai-app
```

---

### ❌ `EntityAlreadyExists` on IAM Role
The role was partially created by a previous attempt. Clean it up and retry:
```bash
aws iam delete-role-policy \
  --role-name RecipeAppLambdaRole \
  --policy-name RecipeAppPermissions 2>/dev/null

aws iam delete-role --role-name RecipeAppLambdaRole 2>/dev/null

./infrastructure/iam.sh
```

---

### ❌ `AccessDeniedException` from Bedrock
Your IAM user is missing AWS Marketplace permissions:
```bash
IAM_USER=$(aws sts get-caller-identity --query "Arn" --output text | cut -d'/' -f2)

aws iam attach-user-policy \
  --user-name $IAM_USER \
  --policy-arn arn:aws:iam::aws:policy/AWSMarketplaceFullAccess
```
Wait 2 minutes then retry.

---

### ❌ `ResourceNotFoundException` — Legacy Model
An older model ID is being used. Verify the correct model ID is set:
```bash
grep "MODEL_ID" backend/lambda_function.py
# Must show: MODEL_ID = "anthropic.claude-haiku-4-5-20251001-v1:0"
```
If not, update and redeploy:
```bash
# macOS
sed -i '' 's/anthropic\.claude-3-haiku-20240307-v1:0/anthropic.claude-haiku-4-5-20251001-v1:0/g' backend/lambda_function.py
sed -i '' 's/anthropic\.claude-3-5-haiku-20241022-v1:0/anthropic.claude-haiku-4-5-20251001-v1:0/g' backend/lambda_function.py

# Linux
sed -i 's/anthropic\.claude-3-haiku-20240307-v1:0/anthropic.claude-haiku-4-5-20251001-v1:0/g' backend/lambda_function.py
sed -i 's/anthropic\.claude-3-5-haiku-20241022-v1:0/anthropic.claude-haiku-4-5-20251001-v1:0/g' backend/lambda_function.py

cd backend && ./deploy.sh && cd ..
```

---

### ❌ Lambda Returns `500`
Check the CloudWatch logs for the exact error message:
```bash
aws logs tail /aws/lambda/RecipeAIFunction --follow
```
Run this in one terminal, then trigger the Lambda test in a second terminal
so the error appears live.

---

### ❌ `403 Forbidden` on CloudFront URL
The distribution may still be propagating. Check its status:
```bash
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='Recipe AI App'].{URL:DomainName,Status:Status}" \
  --output table
```
Wait until **Status** shows `Deployed`, then try the URL again.

---

### ❌ CORS Error in Browser Console
The API URL in `app.js` is incorrect. Verify it:
```bash
grep "API_BASE_URL" frontend/app.js
```
If it shows the placeholder, recreate `app.js` using the commands in
[Section 7](#7-frontend-files) then redeploy:
```bash
chmod +x infrastructure/redeploy_frontend.sh
./infrastructure/redeploy_frontend.sh
```

---

### ❌ `BadRequestException` on API Gateway — Invalid Mapping Expression
The CORS integration response values are not correctly quoted. Delete the
incomplete API and re-run the script:
```bash
# Find and delete the incomplete API
API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='RecipeAIAPI'].id" --output text)

aws apigateway delete-rest-api --rest-api-id $API_ID

# Re-run
./infrastructure/api_gateway.sh
```

---

## 11. Cleanup

Run this when you are finished to remove all resources and avoid ongoing charges:

```bash
cat > infrastructure/cleanup.sh << 'SCRIPT'
#!/bin/bash

REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="recipe-ai-app-${ACCOUNT_ID}"

echo "⚠️  Deleting all resources in 5 seconds. Press Ctrl+C to cancel."
sleep 5

aws lambda delete-function --function-name RecipeAIFunction --region $REGION
echo "✅ Lambda deleted"

aws dynamodb delete-table --table-name RecipeHistory --region $REGION
echo "✅ DynamoDB table deleted"

aws iam delete-role-policy --role-name RecipeAppLambdaRole --policy-name RecipeAppPermissions
aws iam delete-role --role-name RecipeAppLambdaRole
echo "✅ IAM role deleted"

aws s3 rm s3://$BUCKET_NAME --recursive
aws s3api delete-bucket --bucket $BUCKET_NAME --region $REGION
echo "✅ S3 bucket deleted"

API_ID=$(aws apigateway get-rest-apis \
  --query "items[?name=='RecipeAIAPI'].id" --output text)
if [ ! -z "$API_ID" ]; then
  aws apigateway delete-rest-api --rest-api-id $API_ID
  echo "✅ API Gateway deleted"
fi

echo ""
echo "✅ Cleanup complete!"
echo "⚠️  CloudFront must be disabled then deleted manually via the AWS Console."
echo "   Navigate to CloudFront → select distribution → Disable → wait 15 min → Delete"
SCRIPT

chmod +x infrastructure/cleanup.sh
./infrastructure/cleanup.sh
```

> ⚠️ **CloudFront** must be deleted manually — go to the AWS Console →
> **CloudFront** → select the distribution → click **Disable** →
> wait ~15 minutes → click **Delete**.