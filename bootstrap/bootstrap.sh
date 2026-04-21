#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ShopWave — Bootstrap Terraform Remote State
# Run this ONCE before your first terraform plan/apply.
# Requires: AWS CLI configured with sufficient IAM permissions.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="shopwave-terraform-state-${ACCOUNT_ID}"
TABLE="shopwave-terraform-lock"

echo "==> Creating S3 state bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "    Bucket already exists, skipping."
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
  echo "    Created."
fi

echo "==> Enabling versioning on $BUCKET"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

echo "==> Enabling AES-256 encryption on $BUCKET"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'

echo "==> Blocking public access on $BUCKET"
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "==> Creating DynamoDB lock table: $TABLE"
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" 2>/dev/null; then
  echo "    Table already exists, skipping."
else
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  echo "    Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
  echo "    Created."
fi

echo ""
echo "✅  Bootstrap complete!"
echo ""
echo "Add these as GitLab CI/CD variables:"
echo "  TF_STATE_BUCKET  = $BUCKET"
echo "  TF_STATE_LOCK_TABLE = $TABLE"
echo ""
echo "To migrate existing local state (if any):"
echo "  cd ../terraform"
echo "  terraform init \\"
echo "    -backend-config=\"bucket=$BUCKET\" \\"
echo "    -backend-config=\"key=shopwave/prod/terraform.tfstate\" \\"
echo "    -backend-config=\"region=$REGION\" \\"
echo "    -backend-config=\"dynamodb_table=$TABLE\" \\"
echo "    -backend-config=\"encrypt=true\""
