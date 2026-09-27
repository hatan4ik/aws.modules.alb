# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). The setup module creates a disposable VPC with two public
# subnets (tests/integration/setup), the ALB module is applied for real with
# create_http_only = true so no real ACM certificate is needed, the results
# are asserted against the real API, and everything is destroyed at the end
# of the file. deletion_protection is turned off so `terraform destroy` can
# remove the ALB.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "alb-it"
  }
}

run "smoke" {
  variables {
    name              = run.setup.name
    vpc_id            = run.setup.vpc_id
    public_subnet_ids = run.setup.public_subnet_ids
    tags              = run.setup.tags

    # No ACM certificate is available in this suite; the http-only path is
    # the whole reason it needs none. Not the default anyone should reach
    # for outside a test like this one (docs/DESIGN.md).
    create_http_only = true
    certificate_arn  = null

    # Disposable: destroy must be able to remove the ALB.
    deletion_protection = false

    target_groups = {
      app = { port = 8080 }
    }
    default_target_group_key = "app"
  }

  # deletion_protection = false is expected to trip the advisory check on a
  # deliberately disposable integration-test ALB.
  expect_failures = [check.deletion_protection_disabled]

  assert {
    condition     = aws_lb.this.load_balancer_type == "application" && aws_lb.this.internal == false
    error_message = "The real ALB must be an internet-facing application load balancer."
  }

  assert {
    condition     = startswith(output.alb_arn, "arn:") && startswith(output.alb_dns_name, "${run.setup.name}-")
    error_message = "alb_arn and alb_dns_name must reflect the real, newly created ALB."
  }

  assert {
    condition     = output.https_listener_arn == null && output.http_listener_arn != null && startswith(output.http_listener_arn, "arn:")
    error_message = "In HTTP-only mode the real API must report no HTTPS listener and one real HTTP listener."
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].type == "forward"
    error_message = "The HTTP-only listener's default action must forward, never redirect."
  }

  assert {
    condition     = keys(output.target_group_arns) == ["app"] && startswith(output.target_group_arns["app"], "arn:aws:elasticloadbalancing:") && strcontains(output.target_group_arns["app"], ":targetgroup/")
    error_message = "target_group_arns must expose exactly one real target group ARN, keyed \"app\": the interface contract with aws.modules.ecs-service."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].target_type == "ip" && aws_lb_target_group.this["app"].port == 8080
    error_message = "The real target group must be created with the requested port and the ip target type."
  }

  assert {
    condition     = output.security_group_id != null && startswith(output.security_group_id, "sg-")
    error_message = "A real security group must be created."
  }
}
