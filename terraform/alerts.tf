# -----------------
# Alerts (SNS + CloudWatch Alarms)
# -----------------

# SNS topic for alerts
resource "aws_sns_topic" "photo_app_alerts" {
  name = "photo-app-alerts"
}

# Email subscription (you MUST confirm the email from AWS)
resource "aws_sns_topic_subscription" "photo_app_alerts_email" {
  topic_arn = aws_sns_topic.photo_app_alerts.arn
  protocol  = "email"
  endpoint  = "godat1195@icloud.com"
}

# Helper: common alarm actions
locals {
  alarm_actions = [aws_sns_topic.photo_app_alerts.arn]
}

# -----------------
# Lambda alarms
# -----------------

# 1) Errors > 0 in 5 minutes (per function)
resource "aws_cloudwatch_metric_alarm" "lambda_errors_get_upload_url" {
  alarm_name          = "photo-app-get-upload-url-errors"
  alarm_description   = "Lambda errors detected for get-upload-url"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = aws_lambda_function.get_upload_url.function_name
  }

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_finalize_upload" {
  alarm_name          = "photo-app-finalize-upload-errors"
  alarm_description   = "Lambda errors detected for finalize-upload"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = aws_lambda_function.finalize_upload.function_name
  }

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_list_photos" {
  alarm_name          = "photo-app-list-photos-errors"
  alarm_description   = "Lambda errors detected for list-photos"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = aws_lambda_function.list_photos.function_name
  }

  alarm_actions = local.alarm_actions
}

# 2) Duration p95 > 2s for 2 consecutive periods (10 mins total)
resource "aws_cloudwatch_metric_alarm" "lambda_duration_p95_finalize_upload" {
  alarm_name          = "photo-app-finalize-upload-duration-p95"
  alarm_description   = "p95 duration too high for finalize-upload"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2000
  treat_missing_data  = "notBreaching"

  namespace          = "AWS/Lambda"
  metric_name        = "Duration"
  extended_statistic = "p95"
  period             = 300

  dimensions = {
    FunctionName = aws_lambda_function.finalize_upload.function_name
  }

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles_get_upload_url" {
  alarm_name          = "photo-app-get-upload-url-throttles"
  alarm_description   = "Lambda throttles detected for get-upload-url"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/Lambda"
  metric_name = "Throttles"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = aws_lambda_function.get_upload_url.function_name
  }

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles_finalize_upload" {
  alarm_name          = "photo-app-finalize-upload-throttles"
  alarm_description   = "Lambda throttles detected for finalize-upload"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/Lambda"
  metric_name = "Throttles"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = aws_lambda_function.finalize_upload.function_name
  }

  alarm_actions = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles_list_photos" {
  alarm_name          = "photo-app-list-photos-throttles"
  alarm_description   = "Lambda throttles detected for list-photos"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/Lambda"
  metric_name = "Throttles"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    FunctionName = aws_lambda_function.list_photos.function_name
  }

  alarm_actions = local.alarm_actions
}

# -----------------
# API Gateway (HTTP API) alarms
# -----------------

# 4) API 5XX errors > 0 in 5 minutes
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "photo-app-api-5xx"
  alarm_description   = "API Gateway 5XX errors detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  treat_missing_data  = "notBreaching"

  namespace   = "AWS/ApiGateway"
  metric_name = "5XXError"
  statistic   = "Sum"
  period      = 300

  dimensions = {
    ApiId = aws_apigatewayv2_api.photo_api.id
    Stage = aws_apigatewayv2_stage.photo_api_stage.name
  }

  alarm_actions = local.alarm_actions
}

# 5) API latency p95 > 2s for 2 consecutive periods
resource "aws_cloudwatch_metric_alarm" "apigw_latency_p95" {
  alarm_name          = "photo-app-api-latency-p95"
  alarm_description   = "API latency p95 too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2000
  treat_missing_data  = "notBreaching"

  namespace          = "AWS/ApiGateway"
  metric_name        = "Latency"
  extended_statistic = "p95"
  period             = 300

  dimensions = {
    ApiId = aws_apigatewayv2_api.photo_api.id
    Stage = aws_apigatewayv2_stage.photo_api_stage.name
  }

  alarm_actions = local.alarm_actions
}