# The ALB's security group: no inline ingress/egress (aws_security_group with
# no inline rule blocks is created with AWS's default outbound-all rule
# revoked, giving a clean slate), then exactly the rules this module intends
# as separate aws_vpc_security_group_*_rule resources. See docs/DESIGN.md,
# "The security group's egress needs the VPC's CIDR, which is not an input,"
# for why the one data source below exists.

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Controls access to the ${var.name} ALB's listeners; egress is scoped to the VPC CIDR only."
  vpc_id      = var.vpc_id

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "listener" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  description       = "Allow inbound ${each.value.port} from ${each.value.cidr}."

  # This is a deliberately public ALB per ADR-0004: a listener open to
  # 0.0.0.0/0 is the point, not an oversight, and web_acl_arn is available
  # for callers who want a REGIONAL WAFv2 web ACL in front of it. The
  # advisory check.public_without_waf (checks.tf) warns on every plan when
  # this is 0.0.0.0/0 and no web_acl_arn is set, without blocking a caller
  # who has another reason (an upstream Global Accelerator shield, for
  # example) not to attach one here.
  #checkov:skip=CKV_AWS_260:Public ALB by design (ADR-0004); web_acl_arn is optional and the public_without_waf check warns when it and 0.0.0.0/0 are combined.
}

resource "aws_vpc_security_group_egress_rule" "vpc" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic within the VPC only; no unrestricted egress."
}
