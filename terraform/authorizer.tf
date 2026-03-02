# -----------------
# API Gateway JWT Authorizer (Cognito)
# -----------------

resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id          = aws_apigatewayv2_api.photo_api.id
  authorizer_type = "JWT"
  name            = "photo-app-cognito-jwt"

  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.photo_app.id}"
    audience = [aws_cognito_user_pool_client.photo_app.id]
  }
}