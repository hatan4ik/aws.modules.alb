# Access log delivery on and off. The module only points the ALB at a
# bucket the caller already created and granted access to; it never creates
# the bucket or its policy (docs/DESIGN.md).

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
}

variables {
  name              = "app"
  vpc_id            = "vpc-0123456789abcdef0"
  public_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"

  # A non-public CIDR keeps the advisory public_without_waf check quiet: it
  # is not what this file is testing.
  security_group_ingress_cidrs = ["10.0.0.0/16"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}

run "access_logs_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb.this.access_logs) == 0
    error_message = "access_logs must be off (no access_logs block rendered) by default."
  }
}

run "access_logs_on_with_bucket_and_prefix" {
  command = plan
  variables {
    access_logs = {
      bucket_name = "platform-alb-logs"
      prefix      = "app"
    }
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 1
    error_message = "Setting access_logs must render exactly one access_logs block."
  }

  assert {
    condition     = aws_lb.this.access_logs[0].bucket == "platform-alb-logs" && aws_lb.this.access_logs[0].prefix == "app" && aws_lb.this.access_logs[0].enabled == true
    error_message = "The access_logs block must carry the caller's bucket_name and prefix, and be enabled."
  }
}

run "access_logs_on_without_prefix" {
  command = plan
  variables {
    access_logs = {
      bucket_name = "platform-alb-logs"
    }
  }

  assert {
    condition     = aws_lb.this.access_logs[0].bucket == "platform-alb-logs" && aws_lb.this.access_logs[0].enabled == true
    error_message = "access_logs.prefix must be optional."
  }
}
