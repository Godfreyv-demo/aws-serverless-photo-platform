# -----------------
# CloudWatch Dashboard
# -----------------

resource "aws_cloudwatch_dashboard" "photo_app" {
  dashboard_name = "photo-app-dashboard"

  dashboard_body = jsonencode({
    widgets = [

      # -----------------
      # API Gateway Traffic + Errors
      # -----------------
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway: Requests, 4XX, 5XX"
          region = "eu-west-2"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.photo_api.id, "Stage", aws_apigatewayv2_stage.photo_api_stage.name],
            [".", "4XXError", ".", ".", ".", "."],
            [".", "5XXError", ".", ".", ".", "."]
          ]
        }
      },

      # -----------------
      # API Latency
      # -----------------
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "API Gateway: Latency p50 / p95"
          region = "eu-west-2"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.photo_api.id, "Stage", aws_apigatewayv2_stage.photo_api_stage.name, { "stat" : "p50" }],
            [".", "Latency", ".", ".", ".", ".", { "stat" : "p95" }]
          ]
        }
      },

      # -----------------
      # Lambda Errors
      # -----------------
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda: Errors (Sum)"
          region = "eu-west-2"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.get_upload_url.function_name],
            [".", "Errors", "FunctionName", aws_lambda_function.finalize_upload.function_name],
            [".", "Errors", "FunctionName", aws_lambda_function.list_photos.function_name],
          ]
        }
      },

      # -----------------
      # Lambda Duration
      # -----------------
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda: Duration p50 / p95 (ms)"
          region = "eu-west-2"
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.get_upload_url.function_name, { "stat" : "p50" }],
            [".", "Duration", "FunctionName", aws_lambda_function.get_upload_url.function_name, { "stat" : "p95" }],

            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.finalize_upload.function_name, { "stat" : "p50" }],
            [".", "Duration", "FunctionName", aws_lambda_function.finalize_upload.function_name, { "stat" : "p95" }],

            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.list_photos.function_name, { "stat" : "p50" }],
            [".", "Duration", "FunctionName", aws_lambda_function.list_photos.function_name, { "stat" : "p95" }]
          ]
        }
      },

      # -----------------
      # Alarm Status Panel
      # -----------------
      {
        type   = "alarm"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title = "Alarm Status (Photo App)"
          alarms = [
            aws_cloudwatch_metric_alarm.lambda_errors_get_upload_url.arn,
            aws_cloudwatch_metric_alarm.lambda_errors_finalize_upload.arn,
            aws_cloudwatch_metric_alarm.lambda_errors_list_photos.arn,
            aws_cloudwatch_metric_alarm.lambda_duration_p95_finalize_upload.arn,
            aws_cloudwatch_metric_alarm.apigw_5xx.arn,
            aws_cloudwatch_metric_alarm.apigw_latency_p95.arn,
            aws_cloudwatch_metric_alarm.lambda_throttles_get_upload_url.arn,
            aws_cloudwatch_metric_alarm.lambda_throttles_finalize_upload.arn,
            aws_cloudwatch_metric_alarm.lambda_throttles_list_photos.arn,
          ]
        }
      }

    ]
  })
}