# =============================================================================
# edge_alb_waf.tf — Route 53, CloudFront, S3, ALB, AWS WAF
# =============================================================================

# ---------------------------------------------------------------------------
# S3 Bucket — Encrypted Static Assets + RDS Backups
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "static_and_backups" {
  bucket        = "dckap-devops-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # safe for dev; remove for production
  tags          = { Name = "dckap-static-backups" }
}

data "aws_caller_identity" "current" {}

# GDPR/SOC2: Encrypt all objects at rest with AES-256
resource "aws_s3_bucket_server_side_encryption_configuration" "backups_sse" {
  bucket = aws_s3_bucket.static_and_backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# SOC2: Block ALL public access to the bucket
resource "aws_s3_bucket_public_access_block" "backups_block" {
  bucket                  = aws_s3_bucket.static_and_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# CloudFront — CDN with Origin Access Control (OAC)
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "dckap-s3-oac"
  description                       = "OAC for private S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = "DCKAP Hospital App CDN"
  default_root_object = "index.html"
  aliases             = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.static_and_backups.bucket_regional_domain_name
    origin_id                = "S3-dckap-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-dckap-static"
    viewer_protocol_policy = "redirect-to-https" # HTTPS enforced
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  web_acl_id = aws_wafv2_web_acl.main_waf.arn
  tags       = { Name = "dckap-cdn" }
}

# ---------------------------------------------------------------------------
# AWS WAF v2 — SQL Injection + Common Threat Protection
# ---------------------------------------------------------------------------
resource "aws_wafv2_web_acl" "main_waf" {
  name     = "dckap-main-waf"
  scope    = "CLOUDFRONT" # CLOUDFRONT scope must be in us-east-1
  provider = aws.us_east_1

  default_action {
    allow {}
  }

  # AWS Managed Rule: Common threats (XSS, path traversal, etc.)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Rule: SQL Injection protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "dckapWAFMetric"
    sampled_requests_enabled   = true
  }

  tags = { Name = "dckap-main-waf" }
}

# WAF for ALB requires REGIONAL scope
resource "aws_wafv2_web_acl" "alb_waf" {
  name  = "dckap-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ALBCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "dckapALBWAFMetric"
    sampled_requests_enabled   = true
  }

  tags = { Name = "dckap-alb-waf" }
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "app_alb" {
  name               = "dckap-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = false # set true for production
  tags                       = { Name = "dckap-app-alb" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "dckap-app-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "dckap-app-tg" }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Attach WAF to ALB
resource "aws_wafv2_web_acl_association" "alb_waf_assoc" {
  resource_arn = aws_lb.app_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_waf.arn
}

# ---------------------------------------------------------------------------
# Route 53 Health Check + DNS Record
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "app_health" {
  fqdn              = aws_lb.app_alb.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  tags              = { Name = "dckap-alb-health-check" }
}

# NOTE: Requires an existing Route 53 hosted zone for your domain.
# Comment out if you don't have a registered domain yet.
# data "aws_route53_zone" "primary" {
#   name         = var.domain_name
#   private_zone = false
# }
#
# resource "aws_route53_record" "app_dns" {
#   zone_id = data.aws_route53_zone.primary.zone_id
#   name    = var.domain_name
#   type    = "A"
#   alias {
#     name                   = aws_cloudfront_distribution.cdn.domain_name
#     zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
#     evaluate_target_health = true
#   }
# }

# ---------------------------------------------------------------------------
# Provider alias for us-east-1 (required for CloudFront WAF)
# ---------------------------------------------------------------------------
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
