#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# ShopWave — AWS resource cleanup (no Terraform state required)
# Deletes all resources tagged Project=shopwave in dependency order.
#
# Local usage:  AWS_DEFAULT_REGION=us-east-1 ./destroy-manual.sh
# CI usage:     runs non-interactively (confirmation skipped inside GitLab CI)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROJECT="shopwave"
NAME_PREFIX="${PROJECT}-prod"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}==> $*${NC}"; }
warn() { echo -e "${YELLOW}    $*${NC}"; }
skip() { echo    "    (skipped — not found)"; }

tags_filter() { echo "Name=tag:Project,Values=$PROJECT"; }

# ── Confirmation (skipped in GitLab CI) ──────────────────────────────────────
if [[ -n "${CI:-}" ]]; then
  echo -e "${RED}⚠️  CI destroy triggered — deleting ALL Project=$PROJECT resources in $REGION${NC}"
else
  echo -e "${RED}"
  echo "  ⚠️  This will permanently delete all ShopWave AWS resources in $REGION."
  echo "  Resources are identified by tag: Project=$PROJECT"
  echo -e "${NC}"
  read -r -p "  Type 'yes' to continue: " ans
  [[ "$ans" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

# ── 1. Auto Scaling Group ─────────────────────────────────────────────────────
delete_asg() {
  info "1/14  Auto Scaling Group"
  ASG=$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --query "AutoScalingGroups[?contains(Tags[?Key=='Project'].Value,'$PROJECT')].AutoScalingGroupName" \
    --output text)
  if [[ -n "$ASG" ]]; then
    warn "Deleting ASG: $ASG (force-delete terminates instances)"
    aws autoscaling delete-auto-scaling-group \
      --auto-scaling-group-name "$ASG" --force-delete --region "$REGION"
    echo "    Waiting for EC2 instances to terminate..."
    sleep 20
  else skip; fi
}

# ── 2. Remaining EC2 instances (in case ASG was already gone) ────────────────
delete_ec2() {
  info "2/14  Orphaned EC2 Instances"
  INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filter "$(tags_filter)" "Name=instance-state-name,Values=running,stopped,pending" \
    --query "Reservations[].Instances[].InstanceId" --output text)
  if [[ -n "$INSTANCE_IDS" ]]; then
    warn "Terminating: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION"
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$REGION"
    echo "    Instances terminated."
  else skip; fi
}

# ── 3. CloudWatch Alarms ──────────────────────────────────────────────────────
delete_alarms() {
  info "3/14  CloudWatch Alarms"
  ALARMS=$(aws cloudwatch describe-alarms --region "$REGION" \
    --query "MetricAlarms[?contains(AlarmName,'$NAME_PREFIX')].AlarmName" --output text)
  if [[ -n "$ALARMS" ]]; then
    warn "Deleting: $ALARMS"
    aws cloudwatch delete-alarms --alarm-names $ALARMS --region "$REGION"
  else skip; fi
}

# ── 4. ALB → Listeners → Target Groups ───────────────────────────────────────
delete_alb() {
  info "4/14  ALB, Listeners, Target Groups"
  ALB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName,'$NAME_PREFIX')].LoadBalancerArn" \
    --output text)
  if [[ -n "$ALB_ARN" ]]; then
    LISTENERS=$(aws elbv2 describe-listeners \
      --load-balancer-arn "$ALB_ARN" --region "$REGION" \
      --query "Listeners[].ListenerArn" --output text)
    for L in $LISTENERS; do
      warn "Deleting listener: $L"
      aws elbv2 delete-listener --listener-arn "$L" --region "$REGION"
    done
    warn "Deleting ALB: $ALB_ARN"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$REGION"
    aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" --region "$REGION"
  else skip; fi

  TG_ARNS=$(aws elbv2 describe-target-groups --region "$REGION" \
    --query "TargetGroups[?contains(TargetGroupName,'$NAME_PREFIX')].TargetGroupArn" \
    --output text)
  for TG in $TG_ARNS; do
    warn "Deleting target group: $TG"
    aws elbv2 delete-target-group --target-group-arn "$TG" --region "$REGION"
  done
}

# ── 5. Launch Template ────────────────────────────────────────────────────────
delete_launch_template() {
  info "5/14  Launch Template"
  LT=$(aws ec2 describe-launch-templates --region "$REGION" \
    --query "LaunchTemplates[?contains(LaunchTemplateName,'$NAME_PREFIX')].LaunchTemplateId" \
    --output text)
  if [[ -n "$LT" ]]; then
    warn "Deleting: $LT"
    aws ec2 delete-launch-template --launch-template-id "$LT" --region "$REGION"
  else skip; fi
}

# ── 6. RDS Instance ───────────────────────────────────────────────────────────
delete_rds() {
  info "6/14  RDS Instance"
  RDS=$(aws rds describe-db-instances --region "$REGION" \
    --query "DBInstances[?contains(DBInstanceIdentifier,'$NAME_PREFIX')].DBInstanceIdentifier" \
    --output text)
  if [[ -n "$RDS" ]]; then
    warn "Deleting RDS: $RDS (no final snapshot)"
    aws rds delete-db-instance \
      --db-instance-identifier "$RDS" --skip-final-snapshot --region "$REGION"
    echo "    Waiting for RDS deletion (~5 min)..."
    aws rds wait db-instance-deleted --db-instance-identifier "$RDS" --region "$REGION"
  else skip; fi
}

# ── 7. DB Subnet Group ────────────────────────────────────────────────────────
delete_db_subnet_group() {
  info "7/14  DB Subnet Group"
  DBG=$(aws rds describe-db-subnet-groups --region "$REGION" \
    --query "DBSubnetGroups[?contains(DBSubnetGroupName,'$NAME_PREFIX')].DBSubnetGroupName" \
    --output text)
  if [[ -n "$DBG" ]]; then
    warn "Deleting: $DBG"
    aws rds delete-db-subnet-group --db-subnet-group-name "$DBG" --region "$REGION"
  else skip; fi
}

# ── 8. S3 Bucket ──────────────────────────────────────────────────────────────
delete_s3() {
  info "8/14  S3 App Bucket"
  BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?contains(Name,'$NAME_PREFIX')].Name" --output text)
  for BUCKET in $BUCKETS; do
    warn "Force-deleting bucket: $BUCKET"
    aws s3 rb "s3://$BUCKET" --force --region "$REGION"
  done
  [[ -z "$BUCKETS" ]] && skip
}

# ── 9. IAM ────────────────────────────────────────────────────────────────────
delete_iam() {
  info "9/14  IAM Role + Instance Profile"
  PROFILE="${NAME_PREFIX}-ec2-profile"
  ROLE="${NAME_PREFIX}-ec2-role"
  if aws iam get-instance-profile --instance-profile-name "$PROFILE" &>/dev/null; then
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "$PROFILE" --role-name "$ROLE" 2>/dev/null || true
    warn "Deleting profile: $PROFILE"
    aws iam delete-instance-profile --instance-profile-name "$PROFILE"
  fi
  if aws iam get-role --role-name "$ROLE" &>/dev/null; then
    for P in $(aws iam list-role-policies --role-name "$ROLE" \
                 --query PolicyNames --output text); do
      aws iam delete-role-policy --role-name "$ROLE" --policy-name "$P"
    done
    warn "Deleting role: $ROLE"
    aws iam delete-role --role-name "$ROLE"
  fi
}

# ── 10. NAT Gateway + EIP ─────────────────────────────────────────────────────
delete_nat() {
  info "10/14 NAT Gateway + Elastic IP"
  NAT_IDS=$(aws ec2 describe-nat-gateways --region "$REGION" \
    --filter "$(tags_filter)" "Name=state,Values=available,pending" \
    --query "NatGateways[].NatGatewayId" --output text)
  for NAT in $NAT_IDS; do
    warn "Deleting NAT Gateway: $NAT"
    aws ec2 delete-nat-gateway --nat-gateway-id "$NAT" --region "$REGION"
  done
  [[ -n "$NAT_IDS" ]] && { echo "    Waiting ~60s for NAT deletion..."; sleep 65; }

  for EIP in $(aws ec2 describe-addresses --region "$REGION" \
                 --filter "$(tags_filter)" \
                 --query "Addresses[].AllocationId" --output text); do
    warn "Releasing EIP: $EIP"
    aws ec2 release-address --allocation-id "$EIP" --region "$REGION" 2>/dev/null || true
  done
  [[ -z "$NAT_IDS" ]] && skip
}

# ── 11. Security Groups ───────────────────────────────────────────────────────
delete_sgs() {
  info "11/14 Security Groups"
  SG_IDS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filter "$(tags_filter)" \
    --query "SecurityGroups[].GroupId" --output text)
  for SG in $SG_IDS; do
    warn "Deleting SG: $SG"
    aws ec2 delete-security-group --group-id "$SG" --region "$REGION" 2>/dev/null || true
  done
  [[ -z "$SG_IDS" ]] && skip
}

# ── 12. Route Tables + Subnets ────────────────────────────────────────────────
delete_network() {
  info "12/14 Route Tables"
  for RT in $(aws ec2 describe-route-tables --region "$REGION" \
                --filter "$(tags_filter)" \
                --query "RouteTables[].RouteTableId" --output text); do
    for A in $(aws ec2 describe-route-tables --route-table-ids "$RT" --region "$REGION" \
                 --query "RouteTables[0].Associations[?!Main].RouteTableAssociationId" \
                 --output text); do
      aws ec2 disassociate-route-table --association-id "$A" --region "$REGION" 2>/dev/null || true
    done
    warn "Deleting RT: $RT"
    aws ec2 delete-route-table --route-table-id "$RT" --region "$REGION" 2>/dev/null || true
  done

  info "13/14 Subnets"
  for S in $(aws ec2 describe-subnets --region "$REGION" \
               --filter "$(tags_filter)" \
               --query "Subnets[].SubnetId" --output text); do
    warn "Deleting subnet: $S"
    aws ec2 delete-subnet --subnet-id "$S" --region "$REGION" 2>/dev/null || true
  done
}

# ── 13. IGW + VPC ─────────────────────────────────────────────────────────────
delete_vpc() {
  info "14/14 Internet Gateway + VPC"
  for IGW in $(aws ec2 describe-internet-gateways --region "$REGION" \
                 --filter "$(tags_filter)" \
                 --query "InternetGateways[].InternetGatewayId" --output text); do
    VPC_ID=$(aws ec2 describe-internet-gateways \
               --internet-gateway-ids "$IGW" --region "$REGION" \
               --query "InternetGateways[0].Attachments[0].VpcId" --output text)
    [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] && \
      aws ec2 detach-internet-gateway \
        --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region "$REGION"
    warn "Deleting IGW: $IGW"
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$REGION"
  done

  for VPC in $(aws ec2 describe-vpcs --region "$REGION" \
                 --filter "$(tags_filter)" \
                 --query "Vpcs[].VpcId" --output text); do
    warn "Deleting VPC: $VPC"
    aws ec2 delete-vpc --vpc-id "$VPC" --region "$REGION" 2>/dev/null || true
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
delete_asg
delete_ec2
delete_alarms
delete_alb
delete_launch_template
delete_rds
delete_db_subnet_group
delete_s3
delete_iam
delete_nat
delete_sgs
delete_network
delete_vpc

echo ""
echo -e "${GREEN}✅  All ShopWave resources deleted from $REGION.${NC}"
