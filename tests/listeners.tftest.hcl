# The full HTTPS / HTTP-only / redirect matrix (docs/DESIGN.md, "HTTP
# listener existence is driven by redirect_http_to_https, not implied").

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

  security_group_ingress_cidrs = ["10.0.0.0/16"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}

run "https_with_redirect_is_the_default_shape" {
  command = apply
  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && length(aws_lb_listener.http) == 1
    error_message = "Both an HTTPS listener and a redirecting HTTP listener must exist by default."
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].type == "redirect"
    error_message = "The HTTP listener must redirect, not forward, in the default shape."
  }

  assert {
    condition     = output.https_listener_arn != null && output.http_listener_arn != null
    error_message = "Both listener ARN outputs must be populated in the default shape."
  }

  assert {
    condition     = length(local.ingress_rules) == 2 && length(module.security_group.ingress_rule_ids) == 2
    error_message = "Both ports 80 and 443 must be open in the default shape."
  }
}

run "https_only_with_redirect_disabled" {
  command = apply
  variables {
    certificate_arn        = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    redirect_http_to_https = false
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && length(aws_lb_listener.http) == 0
    error_message = "With redirect_http_to_https = false, only the HTTPS listener may exist: no port 80 listener at all."
  }

  assert {
    condition     = output.https_listener_arn != null && output.http_listener_arn == null
    error_message = "http_listener_arn must be null when no HTTP listener exists."
  }

  assert {
    condition     = length(local.ingress_rules) == 1 && values(local.ingress_rules)[0].port == 443
    error_message = "Only port 443 may be open when there is no HTTP listener at all."
  }
}

run "http_only_forwards_directly" {
  command = apply
  variables {
    certificate_arn  = null
    create_http_only = true
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0 && length(aws_lb_listener.http) == 1
    error_message = "create_http_only = true must skip the HTTPS listener entirely and create exactly one HTTP listener."
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].type == "forward"
    error_message = "The HTTP-only listener's default action must forward directly to the default target group, never redirect."
  }

  assert {
    condition     = output.https_listener_arn == null && output.http_listener_arn != null
    error_message = "https_listener_arn must be null and http_listener_arn populated in HTTP-only mode."
  }

  assert {
    condition     = length(local.ingress_rules) == 1 && values(local.ingress_rules)[0].port == 80
    error_message = "Only port 80 may be open in HTTP-only mode."
  }
}

run "additional_certificate_arns_attach_to_the_https_listener" {
  command = apply
  variables {
    certificate_arn             = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
    additional_certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/22222222-2222-2222-2222-222222222222"]
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 1
    error_message = "Every additional_certificate_arns entry must attach to the HTTPS listener via aws_lb_listener_certificate."
  }
}
