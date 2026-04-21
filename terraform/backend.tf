# Partial backend config — bucket/table passed via -backend-config in CI
# Run bootstrap/bootstrap.sh once to create the S3 bucket + DynamoDB table
terraform {
  backend "s3" {}
}
