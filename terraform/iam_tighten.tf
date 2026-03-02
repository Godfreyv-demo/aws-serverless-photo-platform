# -----------------
# Tighten IAM: least privilege per Lambda
# -----------------

data "aws_iam_policy_document" "lambda_s3_list_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.photo_bucket.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["uploads/*", "photos/*"]
    }
  }
}

# --- get_upload_url: only needs PutObject to uploads/*
data "aws_iam_policy_document" "policy_get_upload_url" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.photo_bucket.arn}/uploads/*"]
  }
}

resource "aws_iam_policy" "policy_get_upload_url" {
  name   = "photo-app-policy-get-upload-url"
  policy = data.aws_iam_policy_document.policy_get_upload_url.json
}

resource "aws_iam_role_policy_attachment" "attach_get_upload_url" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.policy_get_upload_url.arn
}

data "aws_iam_policy_document" "policy_delete_photo" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.photo_metadata.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.photo_bucket.arn}/photos/*"]
  }
}

resource "aws_iam_policy" "policy_delete_photo" {
  name   = "photo-app-delete-photo-policy"
  policy = data.aws_iam_policy_document.policy_delete_photo.json
}

resource "aws_iam_role_policy_attachment" "attach_delete_photo" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.policy_delete_photo.arn
}

# --- finalize_upload: needs Head/Get/Copy/Delete from uploads -> photos + DynamoDB PutItem
data "aws_iam_policy_document" "policy_finalize_upload" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:HeadObject"]
    resources = ["${aws_s3_bucket.photo_bucket.arn}/uploads/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.photo_bucket.arn}/photos/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.photo_bucket.arn}/uploads/*"]
  }

  # CopyObject uses source+dest permissions; we already gave Get/Put above
  # Also allow ListBucket with prefix constraints (optional but good hygiene)
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.photo_bucket.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["uploads/*", "photos/*"]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.photo_metadata.arn]
  }
}

resource "aws_iam_policy" "policy_finalize_upload" {
  name   = "photo-app-policy-finalize-upload"
  policy = data.aws_iam_policy_document.policy_finalize_upload.json
}

resource "aws_iam_role_policy_attachment" "attach_finalize_upload" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.policy_finalize_upload.arn
}

# --- list_photos: DynamoDB Query + S3 GetObject for photos/*
data "aws_iam_policy_document" "policy_list_photos" {

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = [aws_dynamodb_table.photo_metadata.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:HeadObject"
    ]
    resources = ["${aws_s3_bucket.photo_bucket.arn}/photos/*"]
  }

}

resource "aws_iam_policy" "policy_list_photos" {
  name   = "photo-app-policy-list-photos"
  policy = data.aws_iam_policy_document.policy_list_photos.json
}

resource "aws_iam_role_policy_attachment" "attach_list_photos" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.policy_list_photos.arn
}