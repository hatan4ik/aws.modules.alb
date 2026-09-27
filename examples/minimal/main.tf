provider "aws" {
  region = var.region
}

module "alb" {
  source = "../../"

  name              = var.name
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  certificate_arn   = var.certificate_arn

  # A public ALB is the point (ADR-0004); set it explicitly rather than
  # relying on the module's default.
  security_group_ingress_cidrs = ["0.0.0.0/0"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}
