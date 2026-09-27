# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "deletion_protection_disabled" {
  assert {
    condition     = var.deletion_protection == true
    error_message = "deletion_protection is disabled: the ALB can be deleted, including by a plan that must replace it, without a manual safeguard. Turn it back on unless this is a deliberately disposable ALB, for example an integration-test fixture."
  }
}

check "public_without_waf" {
  assert {
    condition     = !(contains(var.security_group_ingress_cidrs, "0.0.0.0/0") && var.web_acl_arn == null)
    error_message = "The ALB accepts traffic from 0.0.0.0/0 with no WAFv2 web ACL attached (web_acl_arn is null). This may be intentional, for example when another layer already provides WAF or DDoS protection, but review whether web_acl_arn should be set."
  }
}
