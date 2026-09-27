provider "aws" {
  region = var.region
}

module "alb" {
  source = "../../"

  name              = var.name
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  certificate_arn   = var.certificate_arn

  # This module never creates or owns the web ACL itself (docs/DESIGN.md);
  # web_acl_arn is a plain identifier from aws.modules.waf or elsewhere.
  web_acl_arn = var.web_acl_arn

  security_group_ingress_cidrs = ["0.0.0.0/0"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"
}
