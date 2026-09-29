locals {
  # The caller's Name tag wins; the module only fills the gap.
  tags = merge({ Name = var.name }, var.tags)

  # Listener existence, driven entirely by create_http_only and
  # redirect_http_to_https (see docs/DESIGN.md, "HTTP listener existence").
  https_listener_enabled         = !var.create_http_only
  http_redirect_listener_enabled = !var.create_http_only && var.redirect_http_to_https
  http_only_listener_enabled     = var.create_http_only
  http_listener_enabled          = local.http_redirect_listener_enabled || local.http_only_listener_enabled

  # The listener that actually serves traffic and that listener_rules attach
  # to: HTTPS when it exists, otherwise the HTTP-only listener.
  primary_listener_arn = local.https_listener_enabled ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn

  # Security group ingress: one rule per (active listener port, CIDR) pair.
  active_listener_ports = toset(concat(
    local.https_listener_enabled ? ["443"] : [],
    local.http_listener_enabled ? ["80"] : [],
  ))

  ingress_rules = {
    for pair in setproduct(local.active_listener_ports, var.security_group_ingress_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = tonumber(pair[0]), cidr = pair[1] }
  }

  # Egress: exactly the VPC's own CIDR, never unrestricted. A map (not a
  # single value) because that is the shape aws.modules.security-group's
  # egress_rules input expects (security_group.tf).
  egress_rules = {
    vpc = { cidr = data.aws_vpc.this.cidr_block }
  }

  # Sorted for a deterministic aws_lb.subnets plan diff.
  public_subnet_ids = sort(tolist(var.public_subnet_ids))
}
