# ── S3 bucket — app package ───────────────────────────────────────
resource "aws_s3_bucket" "app" {
  bucket        = "${local.name}-app-${random_id.suffix.hex}"
  force_destroy = true
  tags          = merge(local.tags, { Name = "${local.name}-app-bucket" })
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../app"
  output_path = "${path.module}/app.zip"
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.app.id
  key    = "app.zip"
  source = data.archive_file.app.output_path
  etag   = data.archive_file.app.output_md5
}

# ── IAM — EC2 can read from S3 ────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "s3_read" {
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.app.arn}/*" }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── Launch Template ───────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile { arn = aws_iam_instance_profile.ec2.arn }
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host     = aws_db_instance.mysql.address
    db_name     = var.db_name
    db_user     = var.db_username
    db_password = var.db_password
    app_bucket  = aws_s3_bucket.app.id
    region      = var.region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.tags, { Name = "${local.name}-app" })
  }

  lifecycle { create_before_destroy = true }
}

# ── Auto Scaling Group — 2 AZs ────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "${local.name}-asg"
  min_size            = var.asg_min
  max_size            = var.asg_max
  desired_capacity    = var.asg_desired
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }
}

# ── Scale-out on high CPU ─────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${local.name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app.name }
}
