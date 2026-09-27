# Optional association of a caller-supplied REGIONAL WAFv2 web ACL. This
# module never creates or owns the web ACL itself (docs/DESIGN.md).

resource "aws_wafv2_web_acl_association" "this" {
  count = var.web_acl_arn == null ? 0 : 1

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.web_acl_arn
}
