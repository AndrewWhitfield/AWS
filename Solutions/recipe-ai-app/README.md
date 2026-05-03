# 🍳 AI Recipe Suggester

A beginner-friendly, cloud-native web application built on AWS that uses **Amazon Bedrock (Claude Haiku 4.5)** to suggest recipes based on ingredients you have available. Built on a classic **3-tier architecture** using fully serverless AWS services.

---

## 🏗️ Architecture

```
User Browser
    │
    ▼
CloudFront (HTTPS CDN)
    │  serves static files
    ▼
S3 Bucket (index.html, style.css, app.js)
    │
    │  API calls
    ▼
API Gateway (REST API)
    │  POST /recipes
    │  GET  /history
    ▼
Lambda Function (Python 3.11)
    ├──► Amazon Bedrock (Claude 3 Haiku) — AI recipe generation
    └──► DynamoDB (RecipeHistory table)  — search history
```

| Tier | Service | Purpose |
|------|---------|---------|
| **Presentation** | S3 + CloudFront | Hosts and serves the static frontend |
| **Application** | API Gateway + Lambda + Bedrock | Business logic and AI inference |
| **Data** | DynamoDB | Persists recipe search history |

---

## ✨ Features

- 🤖 AI-generated recipe suggestions powered by **Amazon Bedrock (Claude Haiku 4.5)**
- 🥗 Add up to 20 ingredients via a tag-based input UI
- 📜 Automatic search history saved per browser session
- 📱 Fully responsive, mobile-friendly design
- ⚡ Serverless — no servers to manage or maintain
- 🔒 Secure — S3 bucket is private, served only via CloudFront

---

## 📁 Project Structure

```
recipe-ai-app/
├── infrastructure/
│   ├── iam.sh                  # Creates IAM role and permissions
│   ├── dynamodb.sh             # Creates DynamoDB table
│   ├── api_gateway.sh          # Creates and deploys API Gateway
│   ├── s3.sh                   # Creates S3 bucket and CloudFront distribution
│   ├── redeploy_frontend.sh    # Re-uploads frontend and clears CDN cache
│   └── cleanup.sh              # Tears down all AWS resources
├── backend/
│   ├── lambda_function.py      # Lambda handler (Bedrock + DynamoDB logic)
│   └── deploy.sh               # Packages and deploys the Lambda function
├── frontend/
│   ├── index.html              # Single-page application markup
│   ├── style.css               # Responsive stylesheet
│   └── app.js                  # Frontend logic and API calls
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- An [AWS Account](https://aws.amazon.com/free/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) installed and configured
- [Python 3.11+](https://www.python.org/downloads/)
- [Node.js 18+](https://nodejs.org/) *(optional, for local frontend dev)*
- Bash-compatible terminal (macOS/Linux or WSL on Windows)

### 1. Configure AWS CLI

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, Region (e.g. us-east-1), Output (json)
```

### 2. Enable Amazon Bedrock Model Access

1. Open the [AWS Console](https://console.aws.amazon.com) → **Amazon Bedrock** → **Model Access**
2. Click **Manage Model Access**
3. Enable **Claude Haiku 4.5** (Anthropic)
4. Click **Save Changes** and wait ~1–2 minutes

### 3. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/recipe-ai-app.git
cd recipe-ai-app
```

### 4. Deploy Infrastructure

Run each script in order:

```bash
# Step 1 — IAM Role
chmod +x infrastructure/iam.sh && ./infrastructure/iam.sh

# Step 2 — DynamoDB Table
chmod +x infrastructure/dynamodb.sh && ./infrastructure/dynamodb.sh

# Step 3 — Lambda Function
cd backend && chmod +x deploy.sh && ./deploy.sh && cd ..

# Step 4 — API Gateway
chmod +x infrastructure/api_gateway.sh && ./infrastructure/api_gateway.sh
# ⚠️  Note the API URL printed at the end — save it!
```

### 5. Configure the Frontend

Open `frontend/app.js` and replace the placeholder URL on line 3:

```javascript
// Before
const API_BASE_URL = "https://YOUR_API_ID.execute-api.YOUR_REGION.amazonaws.com/prod";

// After (use the URL from Step 4)
const API_BASE_URL = "https://abc123xyz.execute-api.us-east-1.amazonaws.com/prod";
```

### 6. Deploy the Frontend

```bash
chmod +x infrastructure/s3.sh && ./infrastructure/s3.sh
# 🌐 Your app URL will be printed at the end (live in ~5 minutes)
```

---

## 🔌 API Reference

### `POST /recipes`

Generates AI recipe suggestions based on provided ingredients.

**Request Body**
```json
{
  "userId": "user_abc123",
  "ingredients": ["chicken", "garlic", "lemon"]
}
```

**Response**
```json
{
  "recordId": "550e8400-e29b-41d4-a716-446655440000",
  "ingredients": ["chicken", "garlic", "lemon"],
  "recipe": "**Lemon Garlic Chicken**\n\n..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| `userId` | string | Unique identifier for the user session |
| `ingredients` | array | List of available ingredients (max 20) |

---

### `GET /history?userId={userId}`

Retrieves the last 10 recipe searches for a given user.

**Response**
```json
{
  "history": [
    {
      "userId": "user_abc123",
      "timestamp": "2026-05-03T10:30:00+00:00",
      "recordId": "550e8400-...",
      "ingredients": ["chicken", "garlic", "lemon"],
      "recipe": "..."
    }
  ]
}
```

---

## 🧪 Testing

### Test Lambda Directly

```bash
aws lambda invoke \
  --function-name RecipeAIFunction \
  --payload '{"httpMethod":"POST","path":"/recipes","body":"{\"ingredients\":[\"chicken\",\"garlic\",\"lemon\"],\"userId\":\"test-user\"}"}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json | python3 -m json.tool
```

### Test via API Gateway

```bash
# Generate a recipe
curl -X POST "https://YOUR_API_URL/prod/recipes" \
  -H "Content-Type: application/json" \
  -d '{"ingredients": ["pasta", "tomato", "basil"], "userId": "test-user"}' \
  | python3 -m json.tool

# Retrieve history
curl "https://YOUR_API_URL/prod/history?userId=test-user" | python3 -m json.tool
```

---

## 🔄 Redeploying

### Update the Backend

```bash
cd backend && ./deploy.sh && cd ..
```

### Update the Frontend

After editing any file in `frontend/`:

```bash
./infrastructure/redeploy_frontend.sh
# This re-uploads files and automatically invalidates the CloudFront cache
```

---

## 💰 Estimated Cost

All services fall within the **AWS Free Tier** for typical prototype usage.

| Service | Free Tier | Cost After Free Tier |
|---------|-----------|----------------------|
| Lambda | 1M requests/month | ~$0.20 per 1M requests |
| API Gateway | 1M calls/month | ~$3.50 per 1M calls |
| DynamoDB | 25GB + 200M requests | ~$1.25 per 1M writes |
| S3 | 5GB + 20K requests | Negligible |
| CloudFront | 1TB transfer/month | ~$0.085/GB |
| **Bedrock** | **No free tier** | **~$0.00025 per request** |

> 💡 At typical prototype usage (~100 requests), **total cost is under $0.05**

---

## 🧹 Cleanup

To remove **all** AWS resources and avoid ongoing charges:

```bash
chmod +x infrastructure/cleanup.sh && ./infrastructure/cleanup.sh
```

> ⚠️ The CloudFront distribution must be **disabled then deleted manually** via the AWS Console — this can take ~15 minutes to propagate.

---

## 🛣️ Potential Improvements

| Feature | AWS Service |
|---------|-------------|
| User authentication & accounts | Amazon Cognito |
| Upload a photo of your fridge | S3 + Rekognition |
| Voice input for ingredients | Amazon Transcribe |
| Swap AI models and compare results | Other Bedrock models (Llama, Titan) |
| Custom domain name | Route 53 + ACM |
| CI/CD pipeline | AWS CodePipeline + CodeBuild |

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).