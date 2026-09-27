provider "aws" {
  region = var.region
}

module "alb" {
  source = "../../"

  name              = var.name
  vpc_id            = var.vpc_id
  public_subnet_ids = var.public_subnet_ids
  certificate_arn   = var.certificate_arn

  security_group_ingress_cidrs = ["0.0.0.0/0"]

  # Two target groups: the default catches everything, /api/* and
  # api.example.com both route to the second.
  target_groups = {
    web = { port = 8080 }
    api = { port = 9090 }
  }
  default_target_group_key = "web"

  listener_rules = {
    api-path = {
      priority         = 10
      target_group_key = "api"
      conditions       = { path_patterns = ["/api/*"] }
    }
    api-host = {
      priority         = 20
      target_group_key = "api"
      conditions       = { host_headers = ["api.example.com"] }
    }
  }
}
