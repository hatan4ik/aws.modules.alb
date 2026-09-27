# Path- and host-based routing beyond the default action.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock-alb/50dc6c495c0c9188"
      dns_name   = "mock-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
      arn_suffix = "app/mock-alb/50dc6c495c0c9188"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock-tg/73e2d6bc24d8a067"
    }
  }
}

variables {
  name              = "app"
  vpc_id            = "vpc-0123456789abcdef0"
  public_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"

  security_group_ingress_cidrs = ["10.0.0.0/16"]

  target_groups = {
    web = { port = 8080 }
    api = { port = 9090 }
  }
  default_target_group_key = "web"
}

run "no_rules_by_default" {
  command = apply

  assert {
    condition     = length(aws_lb_listener_rule.this) == 0
    error_message = "listener_rules defaults to {}, so no listener rule resource should be created."
  }
}

run "path_based_rule_attaches_to_the_https_listener" {
  command = apply
  variables {
    listener_rules = {
      api = {
        priority         = 10
        target_group_key = "api"
        conditions       = { path_patterns = ["/api/*", "/v2/api/*"] }
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "Exactly one listener rule must be created for one listener_rules entry."
  }

  assert {
    condition     = aws_lb_listener_rule.this["api"].listener_arn == aws_lb_listener.https[0].arn
    error_message = "A listener rule must attach to the HTTPS listener when one exists."
  }

  assert {
    condition     = aws_lb_listener_rule.this["api"].priority == 10
    error_message = "The rule's priority must match the input."
  }

  assert {
    condition     = toset(one(aws_lb_listener_rule.this["api"].condition).path_pattern[0].values) == toset(["/api/*", "/v2/api/*"])
    error_message = "The rule's path_pattern condition must carry the requested patterns."
  }

  assert {
    condition     = length(aws_lb_listener_rule.this["api"].condition) == 1
    error_message = "A rule with only path_patterns set must render exactly one condition block."
  }
}

run "host_based_rule" {
  command = apply
  variables {
    listener_rules = {
      admin = {
        priority         = 20
        target_group_key = "api"
        conditions       = { host_headers = ["admin.example.com"] }
      }
    }
  }

  assert {
    condition     = toset(one(aws_lb_listener_rule.this["admin"].condition).host_header[0].values) == toset(["admin.example.com"])
    error_message = "The rule's host_header condition must carry the requested hosts."
  }
}

run "rule_attaches_to_http_only_listener_when_no_https_listener_exists" {
  command = apply
  variables {
    certificate_arn  = null
    create_http_only = true
    listener_rules = {
      api = {
        priority         = 10
        target_group_key = "api"
        conditions       = { path_patterns = ["/api/*"] }
      }
    }
  }

  assert {
    condition     = aws_lb_listener_rule.this["api"].listener_arn == aws_lb_listener.http[0].arn
    error_message = "In HTTP-only mode, a listener rule must attach to the HTTP listener, since it is the only listener that exists."
  }
}
