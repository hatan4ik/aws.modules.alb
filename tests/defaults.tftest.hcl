# Baseline secure-by-default posture: one HTTPS listener forwarding to the
# default target group, one HTTP listener that only redirects to it, egress
# scoped to the VPC CIDR, ingress scoped to exactly the two active ports.

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

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}

run "defaults" {
  command = plan

  # The default security_group_ingress_cidrs (["0.0.0.0/0"]) with no
  # web_acl_arn set trips the advisory public_without_waf check on every
  # plan by design (ADR-0004: a public ALB with no WAF is valid, just
  # worth a look). It never blocks; see tests/checks.tftest.hcl for the
  # dedicated coverage of both advisory checks.
  expect_failures = [check.public_without_waf]

  assert {
    condition     = aws_lb.this.internal == false && aws_lb.this.load_balancer_type == "application"
    error_message = "The ALB must be internet-facing (internal = false) and of type application by default."
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true && aws_lb.this.drop_invalid_header_fields == true
    error_message = "deletion_protection and drop_invalid_header_fields must both default to true."
  }

  assert {
    condition     = aws_lb.this.idle_timeout == 60
    error_message = "idle_timeout must default to 60."
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 0
    error_message = "access_logs must be off by default."
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && aws_lb_listener.https[0].port == 443 && aws_lb_listener.https[0].protocol == "HTTPS"
    error_message = "An HTTPS listener on port 443 must exist by default."
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].type == "forward"
    error_message = "The HTTPS listener's default action must forward to the default target group."
  }

  assert {
    condition     = length(aws_lb_listener.http) == 1 && aws_lb_listener.http[0].port == 80 && aws_lb_listener.http[0].default_action[0].type == "redirect"
    error_message = "An HTTP listener on port 80 that only redirects must exist by default."
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].redirect[0].port == "443" && aws_lb_listener.http[0].default_action[0].redirect[0].status_code == "HTTP_301"
    error_message = "The default HTTP listener must redirect to port 443 with a 301."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.vpc.cidr_ipv4 == "10.0.0.0/16" && aws_vpc_security_group_egress_rule.vpc.ip_protocol == "-1"
    error_message = "Egress must be scoped to exactly the VPC's own CIDR, never left unrestricted."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.listener) == 2
    error_message = "Ingress must have exactly one rule per (active port, CIDR) pair: 443 and 80 each paired with the one default CIDR."
  }

  assert {
    condition     = toset([for rule in values(aws_vpc_security_group_ingress_rule.listener) : rule.from_port]) == toset([80, 443])
    error_message = "Ingress rules must cover exactly ports 80 and 443 by default."
  }

  # Whether the listener ARN outputs are populated (rather than their actual
  # value, unknown at plan time for a not-yet-created resource) is proved by
  # tests/listeners.tftest.hcl, which uses command = apply against a mocked
  # provider for exactly that reason.

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No WAF association is created unless web_acl_arn is set."
  }
}
