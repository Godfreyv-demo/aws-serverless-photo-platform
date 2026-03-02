# -----------------
# Cognito (User Pool + Hosted UI)
# -----------------

resource "random_string" "cognito_domain_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_cognito_user_pool" "photo_app" {
  name = "photo-app-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }
}

resource "aws_cognito_user_pool_client" "photo_app" {
  name         = "photo-app-spa-client"
  user_pool_id = aws_cognito_user_pool.photo_app.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  # IMPORTANT: Redirect back to your actual frontend entrypoint
  callback_urls = [
    "http://127.0.0.1:5500/frontend/index.html",
    "http://localhost:5500/frontend/index.html"
  ]

  logout_urls = [
    "http://127.0.0.1:5500/frontend/index.html",
    "http://localhost:5500/frontend/index.html"
  ]
}

resource "aws_cognito_user_pool_domain" "photo_app" {
  domain       = "photo-app-${random_string.cognito_domain_suffix.result}"
  user_pool_id = aws_cognito_user_pool.photo_app.id
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.photo_app.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.photo_app.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.photo_app.domain
}

output "cognito_hosted_ui_issuer" {
  value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.photo_app.id}"
}