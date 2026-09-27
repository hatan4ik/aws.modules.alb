# Every variable validation and every cross-variable precondition, each with
# a failing run via expect_failures. The happy path is covered by
# tests/defaults.tftest.hcl and the other feature test files.

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

  # A non-public CIDR keeps the advisory public_without_waf check quiet in
  # every run below; only the rule actually under test should ever fail.
  security_group_ingress_cidrs = ["10.0.0.0/16"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}

# ---------------------------------------------------------------------------
# name
# ---------------------------------------------------------------------------

run "rejects_name_over_32_characters" {
  command = plan
  variables {
    name = "this-name-is-way-too-long-for-an-alb"
  }
  expect_failures = [var.name]
}

run "rejects_name_with_invalid_characters" {
  command = plan
  variables {
    name = "app_prod"
  }
  expect_failures = [var.name]
}

run "rejects_name_starting_with_internal_prefix" {
  command = plan
  variables {
    name = "internal-app"
  }
  expect_failures = [var.name]
}

run "rejects_name_starting_or_ending_with_hyphen" {
  command = plan
  variables {
    name = "-app"
  }
  expect_failures = [var.name]
}

# ---------------------------------------------------------------------------
# vpc_id / public_subnet_ids
# ---------------------------------------------------------------------------

run "rejects_malformed_vpc_id" {
  command = plan
  variables {
    vpc_id = "not-a-vpc-id"
  }
  expect_failures = [var.vpc_id]
}

run "rejects_fewer_than_two_public_subnet_ids" {
  command = plan
  variables {
    public_subnet_ids = ["subnet-0123456789abcdef0"]
  }
  expect_failures = [var.public_subnet_ids]
}

run "rejects_malformed_public_subnet_id" {
  command = plan
  variables {
    public_subnet_ids = ["subnet-0123456789abcdef0", "not-a-subnet-id"]
  }
  expect_failures = [var.public_subnet_ids]
}

# ---------------------------------------------------------------------------
# certificate_arn / additional_certificate_arns / create_http_only / redirect
# ---------------------------------------------------------------------------

run "rejects_malformed_certificate_arn" {
  command = plan
  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/not-a-uuid"
  }
  expect_failures = [var.certificate_arn]
}

run "rejects_malformed_additional_certificate_arn" {
  command = plan
  variables {
    additional_certificate_arns = ["not-an-arn"]
  }
  expect_failures = [var.additional_certificate_arns]
}

run "rejects_both_create_http_only_and_certificate_arn" {
  command = plan
  variables {
    create_http_only = true
    certificate_arn  = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
  }
  expect_failures = [aws_lb.this]
}

run "rejects_neither_create_http_only_nor_certificate_arn" {
  command = plan
  variables {
    certificate_arn = null
  }
  expect_failures = [aws_lb.this]
}

run "rejects_additional_certificate_arns_with_create_http_only" {
  command = plan
  variables {
    create_http_only            = true
    certificate_arn             = null
    additional_certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"]
  }
  expect_failures = [aws_lb.this]
}

run "rejects_redirect_override_with_create_http_only" {
  command = plan
  variables {
    create_http_only       = true
    certificate_arn        = null
    redirect_http_to_https = false
  }
  expect_failures = [aws_lb.this]
}

# ---------------------------------------------------------------------------
# web_acl_arn
# ---------------------------------------------------------------------------

run "rejects_malformed_web_acl_arn" {
  command = plan
  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/bad/11111111-1111-1111-1111-111111111111"
  }
  expect_failures = [var.web_acl_arn]
}

# ---------------------------------------------------------------------------
# idle_timeout / access_logs
# ---------------------------------------------------------------------------

run "rejects_idle_timeout_out_of_range" {
  command = plan
  variables {
    idle_timeout = 5000
  }
  expect_failures = [var.idle_timeout]
}

run "rejects_empty_access_logs_bucket_name" {
  command = plan
  variables {
    access_logs = { bucket_name = "" }
  }
  expect_failures = [var.access_logs]
}

# ---------------------------------------------------------------------------
# security_group_ingress_cidrs
# ---------------------------------------------------------------------------

run "rejects_empty_security_group_ingress_cidrs" {
  command = plan
  variables {
    security_group_ingress_cidrs = []
  }
  expect_failures = [var.security_group_ingress_cidrs]
}

run "rejects_malformed_security_group_ingress_cidr" {
  command = plan
  variables {
    security_group_ingress_cidrs = ["10.0.0.0"]
  }
  expect_failures = [var.security_group_ingress_cidrs]
}

# ---------------------------------------------------------------------------
# target_groups
# ---------------------------------------------------------------------------

run "rejects_empty_target_groups" {
  command = plan
  variables {
    target_groups = {}
  }
  expect_failures = [var.target_groups]
}

run "rejects_malformed_target_groups_key" {
  command = plan
  variables {
    target_groups            = { "App_1" = { port = 8080 } }
    default_target_group_key = "App_1"
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_port_out_of_range" {
  command = plan
  variables {
    target_groups = { app = { port = 70000 } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_invalid_protocol" {
  command = plan
  variables {
    target_groups = { app = { port = 8080, protocol = "TCP" } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_invalid_target_type" {
  command = plan
  variables {
    target_groups = { app = { port = 8080, target_type = "lambda" } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_deregistration_delay_out_of_range" {
  command = plan
  variables {
    target_groups = { app = { port = 8080, deregistration_delay = 4000 } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_health_check_interval_not_greater_than_timeout" {
  command = plan
  variables {
    target_groups = { app = { port = 8080, health_check = { interval = 5, timeout = 5 } } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_health_check_threshold_out_of_range" {
  command = plan
  variables {
    target_groups = { app = { port = 8080, health_check = { healthy_threshold = 1 } } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_target_groups_health_check_malformed_matcher" {
  command = plan
  variables {
    target_groups = { app = { port = 8080, health_check = { matcher = "ok" } } }
  }
  expect_failures = [var.target_groups]
}

run "rejects_default_target_group_key_not_in_target_groups" {
  command = plan
  variables {
    default_target_group_key = "does-not-exist"
  }
  expect_failures = [aws_lb.this]
}

run "rejects_target_group_name_over_32_characters" {
  command = plan
  variables {
    name                     = "a-very-long-application-name"
    target_groups            = { "a-very-long-target-group-key" = { port = 8080 } }
    default_target_group_key = "a-very-long-target-group-key"
  }
  expect_failures = [aws_lb_target_group.this]
}

# ---------------------------------------------------------------------------
# listener_rules
# ---------------------------------------------------------------------------

run "rejects_listener_rules_priority_out_of_range" {
  command = plan
  variables {
    listener_rules = {
      api = { priority = 0, target_group_key = "app", conditions = { path_patterns = ["/api/*"] } }
    }
  }
  expect_failures = [var.listener_rules]
}

run "rejects_listener_rules_duplicate_priority" {
  command = plan
  variables {
    listener_rules = {
      api   = { priority = 10, target_group_key = "app", conditions = { path_patterns = ["/api/*"] } }
      admin = { priority = 10, target_group_key = "app", conditions = { path_patterns = ["/admin/*"] } }
    }
  }
  expect_failures = [var.listener_rules]
}

run "rejects_listener_rules_with_no_conditions" {
  command = plan
  variables {
    listener_rules = {
      api = { priority = 10, target_group_key = "app", conditions = {} }
    }
  }
  expect_failures = [var.listener_rules]
}

run "rejects_listener_rules_malformed_key" {
  command = plan
  variables {
    listener_rules = {
      "API_rule" = { priority = 10, target_group_key = "app", conditions = { path_patterns = ["/api/*"] } }
    }
  }
  expect_failures = [var.listener_rules]
}

run "rejects_listener_rules_target_group_key_not_in_target_groups" {
  command = plan
  variables {
    listener_rules = {
      api = { priority = 10, target_group_key = "does-not-exist", conditions = { path_patterns = ["/api/*"] } }
    }
  }
  expect_failures = [aws_lb_listener_rule.this]
}
