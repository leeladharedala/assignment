
# Data Engineering Pipeline with Terraform CI/CD

## Overview

This project implements a **real-time data pipeline** for a mock renewable energy data. It leverages AWS services to simulate, process, store, and visualize renewable energy site data.

**Infrastructure** is deployed automatically using **Terraform** through a **GitHub Actions CI/CD pipeline**.

Once its deployed wait for 5mins to get glue-job initiated automatically 

---

## Features

- **Data Generation (AWS Glue)**
    - Generates random energy site data every **5 minutes** and stores it in **S3**.
- **Real-time Processing (AWS Lambda)**
    - Processes new S3 objects → stores processed data in **DynamoDB**.
    - Publishes **SNS alerts** for anomalies.
- **Data Query APIs (FastAPI on Lambda)**
    - Query records by site and time range.
    - Fetch anomalies for a site.
    - Fetch all **net negative energy** records.
- **Visualization**
    - Detailed **charts and graphs** for energy trends, anomaly distribution, and per-site summaries.
- **CI/CD Pipeline (GitHub Actions)**
    - Automates Terraform deployment whenever changes are pushed to `main`.

---


## Terraform CI/CD Workflow

| Trigger                 | Action                             |
|-------------------------|------------------------------------|
| `push` to `main` branch | Runs Terraform init, plan, apply   |

### Workflow Location
```
.github/workflows/terraform-ci.yml
```

---

## Secrets Required (GitHub Settings → Secrets)

| Name                   | Description                       |
|------------------------|-----------------------------------|
| `AWS_ACCESS_KEY_ID`    | AWS IAM user Access Key ID       |
| `AWS_SECRET_ACCESS_KEY`| AWS IAM user Secret Access Key   |

---

## Terraform Outputs

After deployment, Terraform provides:

- `base_url` → API Gateway base URL
- `records_url` → Endpoint for querying records
- `anomalies_url` → Endpoint for anomalies
- `negative_energy_url` → Endpoint for net negative energy records

---

## Sample Output
```
anomalies_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/anomalies"
base_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/"
negative_energy_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/net_negative_energy"
records_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/records"
```
---

## Sample HTTP APIs To Test
**Change to current base_url**
```
records_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/records/site_id009?start=1973-05-19T21:11:59.132412+00:00&end=1972-02-18T19:22:32.555759+00:00"
anomalies_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/anomalies/site_id009"
negative_energy_url = "https://t48z5pl7m4.execute-api.us-east-1.amazonaws.com/net_negative_energy"
```
---

## SNS Email Configuration

**To receive anomaly alerts by email:**

1. **Configure your email address** in main.tf
2. **Check your email inbox** for a confirmation email from AWS SNS after deployment.
3. **Click the confirmation link** in the email to confirm your subscription.
4. Alerts for detected anomalies will be delivered to this email.

---

## Data Visualization

Open the Jupyter notebook:

```
notebooks/Data_Visualization.ipynb
```


## Teardown Instructions

To remove all provisioned AWS resources:

```
terraform destroy
```

---

