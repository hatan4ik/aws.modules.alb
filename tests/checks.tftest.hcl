# Both advisory checks, each isolated so only the check under test fires.

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

  # A non-public CIDR here means public_without_waf never fires in this
  # file's baseline, isolating deletion_protection_disabled below.
  security_group_ingress_cidrs = ["10.0.0.0/8"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}

run "clean_baseline_trips_neither_check" {
  command = plan

  assert {
    condition     = var.deletion_protection == true
    error_message = "Sanity: the baseline must keep deletion_protection at its default true."
  }
}

run "deletion_protection_disabled_warns" {
  command = plan
  variables {
    deletion_protection = false
  }
  expect_failures = [check.deletion_protection_disabled]
}

run "public_with_no_waf_warns" {
  command = plan
  variables {
    security_group_ingress_cidrs = ["0.0.0.0/0"]
    web_acl_arn                  = null
  }
  expect_failures = [check.public_without_waf]
}

run "public_with_waf_attached_does_not_warn" {
  command = plan
  variables {
    security_group_ingress_cidrs = ["0.0.0.0/0"]
    web_acl_arn                  = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/example/11111111-1111-1111-1111-111111111111"
  }
}

run "private_cidr_with_no_waf_does_not_warn" {
  command = plan
  variables {
    security_group_ingress_cidrs = ["10.0.0.0/8"]
  }
}
