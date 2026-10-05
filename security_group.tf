# The ALB's security group and its rules are provisioned by the external
# aws.modules.security-group module rather than hand-rolled here (see its
# docs/CONSUMERS.md for the migration this call implements).
# create_before_destroy_group = true preserves the exact guarantee this
# module's own inline security group had (its lifecycle.create_before_destroy
# block): a forced replacement, most notably a description change, creates
# the new group before destroying the old one instead of the reverse. See
# docs/DESIGN.md, "The security group's egress needs the VPC's CIDR, which is
# not an input," for why the one data source below exists — this module
# performs no data-source reads by design, so the caller (this module) does
# that lookup itself and passes the resolved CIDR straight to the egress
# rule's cidr_ipv4.
#
# TEMPORARY PIN: the ref below is commit 390733e on
# aws.modules.security-group's fix/cbd-group-name-prefix branch, not a tagged
# release. It carries the 1.2.0 fix that names the create_before_destroy
# group with name_prefix = "<name>-" instead of a fixed name, so a
# description-only change no longer fails with InvalidGroup.Duplicate. The
# group's AWS name is therefore generated ("<var.name>-alb-" plus a unique
# suffix, known after apply); its Name tag stays "<var.name>-alb". Re-pin to
# the final released tag's commit once that branch is merged and tagged.
# (The PR was squash-merged to main as 6173619 with an identical module tree,
# but 390733e itself is not on main and no v1.2.0 tag exists yet.)

data "aws_vpc" "this" {
  id = var.vpc_id
}

module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=390733e8c1d6656fbc8092e7fd1b0b6e1eac6e13" # TEMPORARY: unmerged fix/cbd-group-name-prefix (1.2.0 fix), not a release tag

  create_before_destroy_group = true
  name                        = "${var.name}-alb"
  description                 = "Controls access to the ${var.name} ALB's listeners; egress is scoped to the VPC CIDR only."
  vpc_id                      = var.vpc_id

  ingress_rules = {
    for key, rule in local.ingress_rules : key => {
      description = "Allow inbound ${rule.port} from ${rule.cidr}."
      from_port   = rule.port
      to_port     = rule.port
      ip_protocol = "tcp"
      cidr_ipv4   = rule.cidr
    }
  }

  egress_rules = {
    for key, rule in local.egress_rules : key => {
      description = "Allow all outbound traffic within the VPC only; no unrestricted egress."
      ip_protocol = "-1"
      cidr_ipv4   = rule.cidr
    }
  }

  tags = local.tags
}
