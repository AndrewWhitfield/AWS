# Project Documentation
## 3-Tier Prototype — React + API Gateway + Lambda + DynamoDB

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Project Structure](#project-structure)
4. [Backend Files](#backend-files)
   - [template.yaml](#1-backendtemplateyaml)
   - [handler.py](#2-backendsrchandlerpy)
   - [requirements.txt](#3-backendarequirementstxt)
5. [Frontend Files](#frontend-files)
   - [package.json](#4-frontendpackagejson)
   - [vite.config.js](#5-frontendviteconfigjs)
   - [index.html](#6-frontendindexhtml)
   - [client.js](#7-frontendsrcapiclientjs)
   - [main.jsx](#8-frontendsrcmainjsx)
   - [App.jsx](#9-frontendsrcappjsx)
   - [.env.example](#10-frontendenvexample)
6. [Project Root Files](#project-root-files)
   - [.gitignore](#11-gitignore)
7. [How the Files Work Together](#how-the-files-work-together)
8. [Deployment Summary](#deployment-summary)

---

## Project Overview

This project is a serverless 3-tier web application prototype hosted on AWS. It is designed to be simple, cost-effective, and suitable for small-scale usage such as a prototype or proof-of-concept with a small number of users.

The three tiers are:

- **Tier 1 — Presentation:** A React-based single-page application hosted on Amazon S3
- **Tier 2 — Application:** A REST API built with Amazon API Gateway, backed by an AWS Lambda function written in Python
- **Tier 3 — Data:** An Amazon DynamoDB NoSQL database using on-demand billing

---

## Architecture

```
[User's Browser]
      │
      ▼
[S3 Static Website]        ← React frontend (HTML, CSS, JS)
      │
      │ HTTP fetch() calls
      ▼
[API Gateway REST API]     ← Public REST endpoint with CORS restriction
      │
      ▼
[AWS Lambda Function]      ← Python business logic
      │
      ▼
[DynamoDB Table]           ← NoSQL data store
```

---

## Project Structure

```
project/
├── backend/
│   ├── template.yaml          # SAM infrastructure definition
│   ├── src/
│   │   └── handler.py         # Lambda function (Python)
│   └── requirements.txt       # Python dependencies
├── frontend/
│   ├── src/
│   │   ├── App.jsx            # Main React component
│   │   ├── main.jsx           # React entry point
│   │   └── api/
│   │       └── client.js      # API communication layer
│   ├── index.html             # HTML entry point
│   ├── vite.config.js         # Vite build tool configuration
│   ├── package.json           # Node.js dependencies and scripts
│   └── .env.example           # Environment variable template
├── .gitignore                 # Files excluded from Git
└── README.md                  # Setup and deployment instructions
```

---

## Backend Files

### 1. `backend/template.yaml`

**What it is:**
This is the AWS SAM (Serverless Application Model) template. SAM is an AWS framework that lets you define cloud infrastructure using a YAML configuration file rather than manually clicking through the AWS Console. It extends AWS CloudFormation, which is AWS's native infrastructure-as-code service.

**What it does:**
It defines every AWS resource the backend needs:

- **DynamoDB Table (`AppTable`):**
  Defines a DynamoDB table named `app-table`. It uses `PAY_PER_REQUEST` billing (on-demand), meaning you are only charged for actual read/write operations — no upfront capacity planning needed. The table uses a composite key made up of:
  - `pk` (partition key) — used to group related items (e.g., all items share `pk = "ITEM"`)
  - `sk` (sort key) — a unique identifier for each individual record (e.g., a UUID)

- **Lambda Function (`AppFunction`):**
  Defines the Lambda function that runs the backend logic. It points to the `src/` folder for the code and specifies `handler.lambda_handler` as the entry point (the function Python will execute when the Lambda is invoked). It also defines the four API routes that trigger this function: `GET /items`, `GET /items/{id}`, `POST /items`, and `DELETE /items/{id}`. A `DynamoDBCrudPolicy` is attached to give the Lambda permission to read and write to the DynamoDB table.

- **API Gateway (`AppApi`):**
  Defines a REST API with a deployment stage called `dev`. Crucially, it sets the CORS (Cross-Origin Resource Sharing) configuration. This restricts which origins (websites) the browser will allow to call the API. The allowed origin is dynamically set to the S3 website URL, meaning only your hosted React app can make browser-based requests to the API.

- **S3 Bucket (`FrontendBucket`):**
  Defines the S3 bucket that hosts the React frontend. Static website hosting is enabled with `index.html` as both the default and error document (important for single-page React apps where all routes serve the same HTML file). Public access settings are relaxed to allow the website to be publicly viewable.

- **S3 Bucket Policy (`FrontendBucketPolicy`):**
  Attaches a policy to the S3 bucket that explicitly allows any user (`Principal: "*"`) to perform `s3:GetObject` — i.e., read files from the bucket. This is what makes the website publicly accessible.

- **Outputs:**
  At the end of the template, three outputs are declared: `ApiUrl`, `WebsiteUrl`, and `TableName`. These are printed to the terminal after a successful deployment so you can easily find your live URLs.

**Why it matters:**
Without this file, you would have to manually create every resource in the AWS Console, which is time-consuming and error-prone. This file lets you deploy and tear down the entire backend with a single command.

---

### 2. `backend/src/handler.py`

**What it is:**
This is the Python source code for the AWS Lambda function. It is the core of the backend — all API logic lives here.

**What it does:**
The file is structured into several focused sections:

- **Imports and initialisation:**
  Imports the standard Python libraries (`json`, `os`, `uuid`) and the AWS SDK for Python (`boto3`). It initialises a connection to DynamoDB and reads the table name and allowed CORS origin from environment variables set in `template.yaml`.

- **`cors_headers()` function:**
  Returns a dictionary of HTTP headers that must be included in every Lambda response. These headers tell the browser that the response is permitted to be read by the React frontend. Without these headers, the browser would silently block the API response even if the request succeeded.

- **`response()` function:**
  A helper utility that standardises the shape of every HTTP response returned by the Lambda. It takes a status code and a body, attaches the CORS headers, serialises the body to JSON, and returns a properly formatted API Gateway response object.

- **`get_items()` function:**
  Queries DynamoDB for all items where `pk = "ITEM"`. This retrieves the full list of items stored in the table and returns them as a JSON array.

- **`get_item(item_id)` function:**
  Retrieves a single item from DynamoDB using the composite key `pk = "ITEM"` and `sk = item_id`. If the item does not exist, it returns a 404 response.

- **`create_item(body)` function:**
  Parses the incoming JSON request body, generates a new unique ID using `uuid.uuid4()`, constructs a new DynamoDB item with the `pk`, `sk`, and any additional fields from the request body, and writes it to the table. Returns the newly created item with a 201 status code.

- **`delete_item(item_id)` function:**
  Deletes an item from DynamoDB using its composite key. Returns a confirmation message.

- **`lambda_handler(event, context)` function:**
  This is the entry point that AWS calls when the Lambda is triggered. It reads the HTTP method and path parameters from the `event` object passed in by API Gateway, then routes the request to the appropriate function above. It also handles the `OPTIONS` preflight request that browsers send automatically before making cross-origin API calls.

**Why it matters:**
This file is the entire backend logic of the application. It handles all four CRUD operations (Create, Read, Update, Delete — though Update is not implemented in this prototype) and communicates directly with DynamoDB.

---

### 3. `backend/requirements.txt`

**What it is:**
A standard Python dependency file that lists the external libraries the Lambda function requires.

**What it does:**
It specifies `boto3` (the AWS SDK for Python) as a dependency. SAM reads this file during `sam build` to package the correct libraries alongside the Lambda code before deployment.

**Why it matters:**
Although `boto3` is pre-installed in the AWS Lambda Python runtime, explicitly declaring it ensures you are using a known, compatible version and follows best practices for reproducible builds.

---

## Frontend Files

### 4. `frontend/package.json`

**What it is:**
The configuration file for the Node.js project. Every JavaScript/React project has one.

**What it does:**
- Declares the project name and version
- Lists **dependencies** — libraries needed at runtime in the browser:
  - `react` — the core React library
  - `react-dom` — renders React components into the browser DOM
- Lists **devDependencies** — tools only needed during development and building:
  - `vite` — the build tool and development server
  - `@vitejs/plugin-react` — the Vite plugin that adds React/JSX support
- Defines **scripts** that can be run with `npm run`:
  - `dev` — starts the local Vite development server
  - `build` — compiles and bundles the app into the `/dist` folder for deployment
  - `preview` — serves the built `/dist` folder locally for testing before deploying

**Why it matters:**
Running `npm install` reads this file and downloads all listed dependencies into the `node_modules` folder. Without it, the project cannot be built or run.

---

### 5. `frontend/vite.config.js`

**What it is:**
The configuration file for Vite, the build tool used in this project.

**What it does:**
It imports the `defineConfig` helper from Vite and the React plugin from `@vitejs/plugin-react`. The configuration registers the React plugin, which enables:
- JSX syntax support (the HTML-like syntax used in React components)
- Fast Refresh / Hot Module Replacement during development (changes appear in the browser instantly without a full page reload)

**Why it matters:**
Without this configuration file, Vite would not know to process React/JSX files. It is the bridge between Vite and React.

---

### 6. `frontend/index.html`

**What it is:**
The single HTML file that serves as the entry point for the entire React application.

**What it does:**
- Declares a standard HTML5 document structure
- Sets the page title to "Prototype App"
- Contains a `<div id="root"></div>` — this is the empty container where React will inject and render the entire application
- Loads `src/main.jsx` as a JavaScript module, which bootstraps the React application

**Why it matters:**
This is the only HTML file in the project. React is a single-page application (SPA) framework — it renders everything dynamically inside the `#root` div using JavaScript. Vite uses this file as the starting point when building the `/dist` output.

---

### 7. `frontend/src/api/client.js`

**What it is:**
A dedicated API communication module that abstracts all HTTP calls to the backend.

**What it does:**
- Reads the API Gateway base URL from the `VITE_API_URL` environment variable (set in your `.env` file)
- Defines a generic `request()` function that:
  - Constructs the full URL by combining the base URL and the given path
  - Sets the `Content-Type: application/json` header on all requests
  - Throws a meaningful error if the response status is not OK
  - Parses and returns the JSON response body
- Exports an `api` object with four named methods that map to the backend routes:
  - `getItems()` — calls `GET /items`
  - `getItem(id)` — calls `GET /items/{id}`
  - `createItem(data)` — calls `POST /items` with a JSON body
  - `deleteItem(id)` — calls `DELETE /items/{id}`

**Why it matters:**
By centralising all API calls in one file, the rest of the React application never needs to know the details of how HTTP requests are made. If the API URL or structure changes, only this file needs updating. This is a standard separation-of-concerns pattern in frontend development.

---

### 8. `frontend/src/main.jsx`

**What it is:**
The JavaScript entry point for the React application.

**What it does:**
- Imports `React` and `ReactDOM`
- Imports the root `App` component
- Uses `ReactDOM.createRoot()` to target the `<div id="root">` element in `index.html`
- Renders the `App` component inside `React.StrictMode`, which enables additional development-time warnings and checks

**Why it matters:**
This is the file that actually starts the React application. Vite loads this file first (as referenced by `index.html`), and it kicks off the entire component rendering process.

---

### 9. `frontend/src/App.jsx`

**What it is:**
The main React component and the entire user interface of the prototype application.

**What it does:**
It is a functional React component that manages the full lifecycle of the items UI:

- **State management** using React's `useState` hook:
  - `items` — the list of items retrieved from the API
  - `inputValue` — the current value typed in the input field
  - `loading` — a boolean that tracks whether an API call is in progress
  - `error` — stores any error message to display to the user

- **`loadItems()` function:**
  Calls `api.getItems()`, updates the `items` state with the response, and manages the `loading` and `error` states around the call.

- **`useEffect` hook:**
  Calls `loadItems()` automatically when the component first renders, so the list of items is fetched and displayed as soon as the page loads.

- **`handleCreate()` function:**
  Called when the user submits the form. It calls `api.createItem()` with the current input value, clears the input field, and refreshes the item list.

- **`handleDelete()` function:**
  Called when the user clicks a Delete button. It calls `api.deleteItem()` with the item's ID and refreshes the list.

- **Rendered UI:**
  Returns a simple interface containing a text input form for adding items, an error message display area, a loading indicator, a "no items" message when the list is empty, and a list of items each with a Delete button. All styling is applied using inline style objects for simplicity.

**Why it matters:**
This is the only visible part of the application that users interact with. It ties together the API client, React state, and the rendered interface into a complete working prototype.

---

### 10. `frontend/.env.example`

**What it is:**
A template file showing which environment variables the frontend application requires.

**What it does:**
It contains a placeholder for the `VITE_API_URL` variable, which must be set to the API Gateway URL output after backend deployment. The `VITE_` prefix is required by Vite — only variables with this prefix are exposed to the browser-side JavaScript code.

**Why it matters:**
The actual `.env` file (which contains real values) is excluded from version control via `.gitignore`. The `.env.example` file acts as a safe, committable reference so that any developer setting up the project knows exactly which variables they need to configure.

---

## Project Root Files

### 11. `.gitignore`

**What it is:**
A configuration file that tells Git which files and folders to exclude from version control.

**What it does:**
It excludes the following:

- `.DS_Store` and `**/.DS_Store` — macOS system files automatically created by Finder that have no relevance to the project
- `.env` — contains real API URLs and potentially sensitive configuration; should never be committed to a repository
- `frontend/node_modules/` — the folder containing all downloaded npm packages; this can be hundreds of megabytes and is always regenerated by running `npm install`
- `frontend/dist/` — the compiled build output generated by `npm run build`; this is regenerated on every build and does not belong in source control
- `backend/.aws-sam/` — the SAM build output folder generated by `sam build`; similar to `dist`, it is always regenerated and does not belong in source control

**Why it matters:**
Without this file, running `git add .` would accidentally commit thousands of unnecessary files, bloating the repository and potentially exposing sensitive configuration values.

---

## How the Files Work Together

The following describes the end-to-end flow when a user interacts with the application:

```
1. User opens the S3 website URL in their browser
        │
        ▼
2. Browser loads index.html from S3
        │
        ▼
3. index.html loads main.jsx via Vite's bundled output
        │
        ▼
4. main.jsx renders <App /> into the #root div
        │
        ▼
5. App.jsx calls loadItems() on first render via useEffect
        │
        ▼
6. loadItems() calls api.getItems() in client.js
        │
        ▼
7. client.js makes a GET /items HTTP request to API Gateway
        │
        ▼
8. API Gateway receives the request, checks CORS origin,
   and triggers the Lambda function
        │
        ▼
9. handler.py receives the event, routes to get_items(),
   queries DynamoDB for all items where pk = "ITEM"
        │
        ▼
10. DynamoDB returns the items to Lambda
        │
        ▼
11. Lambda returns a JSON response with CORS headers
    back through API Gateway to the browser
        │
        ▼
12. client.js resolves the response and returns the data
        │
        ▼
13. App.jsx updates the items state, React re-renders
    the list of items on screen
```

---

## Deployment Summary

| Step | Command | Purpose |
|---|---|---|
| Configure AWS | `aws configure` | Authenticate AWS CLI with your account |
| Build backend | `sam build` | Package Lambda code and dependencies |
| Deploy backend | `sam deploy --guided` | Create all AWS resources via CloudFormation |
| Install frontend deps | `npm install` | Download React and Vite packages |
| Configure frontend | Edit `.env` | Set the API Gateway URL |
| Build frontend | `npm run build` | Compile React app into `/dist` |
| Deploy frontend | `aws s3 sync ./dist s3://bucket-name --delete` | Upload built files to S3 |

---

## Tear Down

To remove all AWS resources:

```bash
# Step 1 — Empty the S3 bucket
aws s3 rm s3://my-prototype-frontend-<YOUR_ACCOUNT_ID> --recursive

# Step 2 — Delete the CloudFormation stack
cd backend
sam delete --stack-name my-prototype
```

After teardown, verify removal by checking:
