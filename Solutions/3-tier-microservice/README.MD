# 3-Tier Prototype — React + API Gateway + Lambda + DynamoDB

A simple, cost-effective 3-tier serverless prototype built on AWS.

## Architecture

```
[React Frontend]  →  [API Gateway]  →  [Lambda]  →  [DynamoDB]
     (S3)               (REST)          (Python)    (On-Demand)
```

## Project Structure

```
project/
├── backend/
│   ├── template.yaml       # SAM infrastructure definition
│   ├── src/
│   │   └── handler.py      # Lambda function
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── App.jsx
│   │   ├── main.jsx
│   │   └── api/
│   │       └── client.js
│   ├── index.html
│   ├── vite.config.js
│   └── package.json
└── README.md
```

---

## Prerequisites

Ensure the following are installed before starting:

| Tool | Version | Install |
|---|---|---|
| Node.js | 18+ | https://nodejs.org |
| Python | 3.12+ | https://python.org |
| AWS CLI | v2 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| AWS SAM CLI | Latest | https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html |

---

## Setup & Deployment

### 1. Configure AWS CLI

```bash
aws configure
```

Enter your:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g. `eu-west-1`)
- Output format: `json`

---

### 2. Deploy the Backend

```bash
cd backend

# Build the SAM application
sam build

# Deploy (first time — guided setup)
sam deploy --guided
```

When prompted:
- **Stack Name:** `my-prototype`
- **AWS Region:** `eu-west-1` (or your preferred region)
- **Confirm changes:** `Y`
- **Allow SAM to create IAM roles:** `Y`
- **Save config to samconfig.toml:** `Y`

At the end of deployment, note the printed outputs:

```
ApiUrl     = https://xxxxxxxxxx.execute-api.eu-west-1.amazonaws.com/dev
WebsiteUrl = http://my-prototype-frontend-123456789.s3-website-eu-west-1.amazonaws.com
TableName  = app-table
```

---

### 3. Configure the Frontend

```bash
cd ../frontend

# Install dependencies
npm install

# Create your environment file
cp .env.example .env
```

Edit `.env` and paste in your `ApiUrl` from Step 2:

```
VITE_API_URL=https://xxxxxxxxxx.execute-api.eu-west-1.amazonaws.com/dev
```

---

### 4. Build and Deploy the Frontend

```bash
# Build the React app
npm run build

# Sync the build output to S3
aws s3 sync ./dist s3://my-prototype-frontend-<YOUR_ACCOUNT_ID> --delete
```

Replace `<YOUR_ACCOUNT_ID>` with your AWS account ID (visible in the SAM deploy output).

---

### 5. Open the App

Open the `WebsiteUrl` from Step 2 in your browser and share it with your testers.

---

## Redeployment

After making changes, redeploy using the following:

### Backend Changes (Lambda / SAM)

```bash
cd backend
sam build
sam deploy
```

### Frontend Changes (React)

```bash
cd frontend
npm run build
aws s3 sync ./dist s3://my-prototype-frontend-<YOUR_ACCOUNT_ID> --delete
```

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/items` | Get all items |
| `GET` | `/items/{id}` | Get a single item by ID |
| `POST` | `/items` | Create a new item |
| `DELETE` | `/items/{id}` | Delete an item by ID |

### Example POST body

```json
{
  "name": "My new item"
}
```

---

## Cost Estimate

All services used fall within the AWS free tier for low-volume prototype usage:

| Service | Free Tier |
|---|---|
| S3 | 5GB storage, 20k GET requests/month |
| API Gateway | 1M API calls/month (12 months) |
| Lambda | 1M invocations/month (always free) |
| DynamoDB | 25GB storage, 25 WCU/RCU (always free) |

> **Expected monthly cost for 2-3 users: ~$0.00**

---

## Tear Down

To remove all AWS resources and avoid any future charges:

```bash
# Empty the S3 bucket first
aws s3 rm s3://my-prototype-frontend-<YOUR_ACCOUNT_ID> --recursive

# Delete the SAM stack (removes API Gateway, Lambda, DynamoDB)
cd backend
sam delete --stack-name my-prototype
```

---

## Notes

- CORS is locked to the S3 website URL — only the hosted frontend can call the API via a browser
- DynamoDB uses on-demand billing — no capacity planning required
- This prototype is not intended for production use without adding authentication, HTTPS, and WAF