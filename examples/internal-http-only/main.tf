provider "aws" {
  region = var.region
}

module "alb" {
  source = "../../"

  name     = var.name
  internal = true

  vpc_id            = var.vpc_id
  public_subnet_ids = var.private_subnet_ids

  # The narrow escape hatch (docs/DESIGN.md): no ACM certificate, no HTTPS
  # listener, plain HTTP only. Not a default anyone should reach for outside
  # a documented internal-only need such as this one.
  create_http_only = true
  certificate_arn  = null

  # Scoped to the VPC, not the module's public 0.0.0.0/0 default: this ALB
  # is internal and unencrypted, so it must never be reachable from outside
  # the VPC.
  security_group_ingress_cidrs = [var.vpc_cidr]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}
