terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------
# S3 Bucket
# -----------------
resource "aws_s3_bucket" "photo_bucket" {
  bucket = "godfrey-photo-app-2026-84729"
}

# Defense in depth: block public access
resource "aws_s3_bucket_public_access_block" "photo_bucket_pab" {
  bucket = aws_s3_bucket.photo_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Strong default: disable ACLs entirely (bucket owner enforced)
resource "aws_s3_bucket_ownership_controls" "photo_bucket_ownership" {
  bucket = aws_s3_bucket.photo_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Default encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "photo_bucket_sse" {
  bucket = aws_s3_bucket.photo_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "photo_bucket_versioning" {
  bucket = aws_s3_bucket.photo_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle cleanup for uploads/
resource "aws_s3_bucket_lifecycle_configuration" "photo_bucket_cleanup" {
  bucket = aws_s3_bucket.photo_bucket.id

  rule {
    id     = "delete-uploads-after-1-day"
    status = "Enabled"

    filter {
      prefix = "uploads/"
    }

    expiration {
      days = 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Enforce TLS for S3 access (good production signal)
data "aws_iam_policy_document" "photo_bucket_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.photo_bucket.arn,
      "${aws_s3_bucket.photo_bucket.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "photo_bucket_policy" {
  bucket = aws_s3_bucket.photo_bucket.id
  policy = data.aws_iam_policy_document.photo_bucket_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.photo_bucket_pab]
}

# S3 CORS (for browser PUT/GET via presigned URLs)
resource "aws_s3_bucket_cors_configuration" "photo_bucket_cors" {
  bucket = aws_s3_bucket.photo_bucket.id

  cors_rule {
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# -----------------
# DynamoDB
# -----------------
resource "aws_dynamodb_table" "photo_metadata" {
  name         = "photo-metadata"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "pk"
  range_key = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# -----------------
# IAM for Lambda
# -----------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "photo-app-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------
# Lambda packaging
# -----------------
data "archive_file" "get_upload_url_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_upload_url.py"
  output_path = "${path.module}/lambda/get_upload_url.zip"
}

data "archive_file" "list_photos_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/list_photos.py"
  output_path = "${path.module}/lambda/list_photos.zip"
}

data "archive_file" "finalize_upload_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/finalize_upload.py"
  output_path = "${path.module}/lambda/finalize_upload.zip"
}

data "archive_file" "delete_photo_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/delete_photo.py"
  output_path = "${path.module}/lambda/delete_photo.zip"
}

# -----------------
# Lambda functions
# -----------------
resource "aws_lambda_function" "get_upload_url" {
  function_name = "photo-app-get-upload-url"
  role          = aws_iam_role.lambda_role.arn
  handler       = "get_upload_url.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.get_upload_url_zip.output_path
  source_code_hash = data.archive_file.get_upload_url_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.photo_bucket.bucket
    }
  }
}

resource "aws_lambda_function" "list_photos" {
  function_name = "photo-app-list-photos"
  role          = aws_iam_role.lambda_role.arn
  handler       = "list_photos.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.list_photos_zip.output_path
  source_code_hash = data.archive_file.list_photos_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.photo_metadata.name
      BUCKET_NAME = aws_s3_bucket.photo_bucket.bucket
    }
  }
}

resource "aws_lambda_function" "finalize_upload" {
  function_name = "photo-app-finalize-upload"
  role          = aws_iam_role.lambda_role.arn
  handler       = "finalize_upload.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.finalize_upload_zip.output_path
  source_code_hash = data.archive_file.finalize_upload_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.photo_metadata.name
      BUCKET_NAME = aws_s3_bucket.photo_bucket.bucket
    }
  }
}

resource "aws_lambda_function" "delete_photo" {
  function_name = "photo-app-delete-photo"
  role          = aws_iam_role.lambda_role.arn
  handler       = "delete_photo.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.delete_photo_zip.output_path
  source_code_hash = data.archive_file.delete_photo_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.photo_metadata.name
      BUCKET_NAME = aws_s3_bucket.photo_bucket.bucket
    }
  }
}

# -----------------
# Observability: CloudWatch log retention for Lambdas
# -----------------
resource "aws_cloudwatch_log_group" "lg_get_upload_url" {
  name              = "/aws/lambda/${aws_lambda_function.get_upload_url.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "lg_list_photos" {
  name              = "/aws/lambda/${aws_lambda_function.list_photos.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "lg_finalize_upload" {
  name              = "/aws/lambda/${aws_lambda_function.finalize_upload.function_name}"
  retention_in_days = 14
}

# -----------------
# API Gateway (HTTP API)
# -----------------
resource "aws_apigatewayv2_api" "photo_api" {
  name          = "photo-app-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
  }
}

# API Gateway access logs
resource "aws_cloudwatch_log_group" "apigw_access" {
  name              = "/aws/apigw/photo-app"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "photo_api_stage" {
  api_id      = aws_apigatewayv2_api.photo_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access.arn
    format = jsonencode({
      requestId    = "$context.requestId"
      ip           = "$context.identity.sourceIp"
      requestTime  = "$context.requestTime"
      httpMethod   = "$context.httpMethod"
      routeKey     = "$context.routeKey"
      status       = "$context.status"
      latencyMs    = "$context.responseLatency"
      responseSize = "$context.responseLength"
      userAgent    = "$context.identity.userAgent"
    })
  }
}

# -----------------
# Integrations + routes
# -----------------

# --- GET /upload-url ---
resource "aws_apigatewayv2_integration" "upload_url_integration" {
  api_id                 = aws_apigatewayv2_api.photo_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_upload_url.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_url_route" {
  api_id    = aws_apigatewayv2_api.photo_api.id
  route_key = "GET /upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.upload_url_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

resource "aws_lambda_permission" "allow_apigw_invoke_upload_url" {
  statement_id  = "AllowAPIGatewayInvokeUploadUrl"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_upload_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.photo_api.execution_arn}/*/GET/upload-url"
}

# --- GET /photos ---
resource "aws_apigatewayv2_integration" "list_photos_integration" {
  api_id                 = aws_apigatewayv2_api.photo_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list_photos.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "list_photos_route" {
  api_id    = aws_apigatewayv2_api.photo_api.id
  route_key = "GET /photos"
  target    = "integrations/${aws_apigatewayv2_integration.list_photos_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

resource "aws_lambda_permission" "allow_apigw_invoke_list_photos" {
  statement_id  = "AllowAPIGatewayInvokeListPhotos"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_photos.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.photo_api.execution_arn}/*/GET/photos"
}

# --- DELETE /photos ---
resource "aws_apigatewayv2_integration" "delete_photo_integration" {
  api_id                 = aws_apigatewayv2_api.photo_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.delete_photo.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "delete_photo_route" {
  api_id    = aws_apigatewayv2_api.photo_api.id
  route_key = "DELETE /photos"
  target    = "integrations/${aws_apigatewayv2_integration.delete_photo_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

resource "aws_lambda_permission" "allow_apigw_invoke_delete_photo" {
  statement_id  = "AllowAPIGatewayInvokeDeletePhoto"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_photo.function_name
  principal     = "apigateway.amazonaws.com"

  # Use method-specific source ARN (matches how you did GET and POST)
  source_arn = "${aws_apigatewayv2_api.photo_api.execution_arn}/*/DELETE/photos"
}

# --- POST /photos (legacy) ---

# --- POST /finalize ---
resource "aws_apigatewayv2_integration" "finalize_upload_integration" {
  api_id                 = aws_apigatewayv2_api.photo_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.finalize_upload.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "finalize_upload_route" {
  api_id    = aws_apigatewayv2_api.photo_api.id
  route_key = "POST /finalize"
  target    = "integrations/${aws_apigatewayv2_integration.finalize_upload_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

resource "aws_lambda_permission" "allow_apigw_invoke_finalize_upload" {
  statement_id  = "AllowAPIGatewayInvokeFinalizeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finalize_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.photo_api.execution_arn}/*/POST/finalize"
}

# Output the API endpoint
output "photo_api_base_url" {
  value = aws_apigatewayv2_api.photo_api.api_endpoint
}