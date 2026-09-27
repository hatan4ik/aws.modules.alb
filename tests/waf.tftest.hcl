# WAFv2 web ACL association on and off. This module never creates the web
# ACL itself (docs/DESIGN.md); web_acl_arn is a plain, caller-supplied ARN.

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

run "no_association_by_default" {
  command = plan

  # No web_acl_arn and the default public 0.0.0.0/0 CIDR trips the advisory
  # check by design; see tests/checks.tftest.hcl for dedicated coverage.
  expect_failures = [check.public_without_waf]

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No aws_wafv2_web_acl_association may exist when web_acl_arn is unset."
  }
}

run "association_created_when_web_acl_arn_is_set" {
  command = plan
  variables {
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/example/11111111-1111-1111-1111-111111111111"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "Exactly one aws_wafv2_web_acl_association must exist when web_acl_arn is set."
  }

  assert {
    condition     = aws_wafv2_web_acl_association.this[0].web_acl_arn == var.web_acl_arn
    error_message = "The association's web_acl_arn must equal the input verbatim."
  }
}
