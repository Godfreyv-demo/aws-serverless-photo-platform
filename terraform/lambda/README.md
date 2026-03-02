# Secure Serverless Photo Platform (AWS + Terraform)

A production-minded serverless photo application built using AWS services and deployed entirely with Terraform.

This project demonstrates secure upload patterns, JWT-based authentication, per-user data isolation, infrastructure as code, and operational observability — all core skills required for Cloud / DevOps engineering roles.

---

## Overview

This application allows authenticated users to:

- Log in via Amazon Cognito (OAuth2 Authorization Code Flow)
- Upload images securely using presigned S3 URLs
- Finalize uploads server-side with strict validation
- View only their own photos
- Delete their own photos
- Trigger monitored and observable backend operations

The system enforces strict ownership and avoids common serverless pitfalls such as orphaned S3 objects and insecure client-side validation.

---

## Architecture

```mermaid
flowchart LR
  U[User Browser SPA] -->|Login| C[Cognito Hosted UI]
  U -->|JWT Bearer Token| AGW[API Gateway HTTP API<br/>JWT Authorizer]

  AGW --> L1[Lambda: get_upload_url]
  AGW --> L2[Lambda: finalize_upload]
  AGW --> L3[Lambda: list_photos]
  AGW --> L4[Lambda: delete_photo]

  L1 --> S3[(S3 Bucket<br/>uploads/<sub>/...)]
  L2 --> S3
  L2 --> DDB[(DynamoDB<br/>photo-metadata)]
  L3 --> DDB
  L3 --> S3
  L4 --> S3
  L4 --> DDB

  AGW --> CW[(CloudWatch Logs<br/>API Access Logs)]
  L1 --> CW
  L2 --> CW
  L3 --> CW
  L4 --> CW

  CW --> AL[CloudWatch Alarms + Dashboard]
  AL --> SNS[SNS Email Alerts]