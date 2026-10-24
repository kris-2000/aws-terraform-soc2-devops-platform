# =============================================================================
# iam_cloudwatch.tf — Least-Privilege IAM + CloudWatch Alarms/Logs
# =============================================================================

# ---------------------------------------------------------------------------
# IAM Role: EC2 Least-Privilege (CloudWatch Logs + S3 Backup Read)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ec2_least_privilege" {
  name = "dckap-ec2-least-privilege-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "dckap-ec2-role" }
}

# Inline policy: only the exact permissions the EC2 needs
resource "aws_iam_role_policy" "ec2_policy" {
  name = "dckap-ec2-policy"
  role = aws_iam_role.ec2_least_privilege.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "S3BackupWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.static_and_backups.arn,
          "${aws_s3_bucket.static_and_backups.arn}/backups/*"
        ]
      },
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:GetMessages"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "dckap-ec2-instance-profile"
  role = aws_iam_role.ec2_least_privilege.name
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group — Application Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/dckap/hospital-app"
  retention_in_days = 30 # SOC2: 30-day log retention minimum
  tags              = { Name = "dckap-app-logs" }
}

resource "aws_cloudwatch_log_group" "rds_logs" {
  name              = "/aws/rds/instance/dckap-hospital-db/general"
  retention_in_days = 30
  tags              = { Name = "dckap-rds-logs" }
}

# ---------------------------------------------------------------------------
# SNS Topic for Alarms
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "ops_alerts" {
  name = "dckap-ops-alerts"
  tags = { Name = "dckap-ops-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = "krishnaprasadjune@gmail.com"
}

# ---------------------------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------------------------

# Alarm 1: EC2 CPU > 80%
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  alarm_name          = "dckap-ec2-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU utilisation >= 80% for 4 minutes"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]

  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  tags = { Name = "dckap-ec2-cpu-alarm" }
}

# Alarm 2: ALB 5XX errors > 5
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "dckap-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "ALB is returning > 5 HTTP 5XX errors per minute"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
  }

  tags = { Name = "dckap-alb-5xx-alarm" }
}

# Alarm 3: RDS CPU > 75%
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "dckap-rds-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "RDS CPU utilisation >= 75%"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.mysql_rds.identifier
  }

  tags = { Name = "dckap-rds-cpu-alarm" }
}
