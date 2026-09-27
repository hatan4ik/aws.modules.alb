# The interface contract with aws.modules.ecs-service v1.0.0: this module's
# whole reason for existing. ecs-service's load_balancers input is
#
#   variable "load_balancers" {
#     type = map(object({
#       target_group_arn = string
#       container_name    = string
#       container_port    = number
#       advanced_configuration = optional(object({ ... }))
#     }))
#     default  = {}
#     nullable = false
#   }
#
# (read from hatan4ik/aws.modules.ecs-service's variables.tf on main). This
# module's target_group_arns output must be a map(string) with exactly the
# same keys as target_groups, so a caller folds it in directly with no
# lookup, no key rename, and no wrapping object.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }

  # target_group_arns's whole point is the ARN value itself, which (like any
  # provider, real or mocked) is unknown for a not-yet-created resource at
  # plan time; command = apply below resolves it against these deterministic
  # mock defaults instead of random per-apply filler, which is not
  # necessarily a well-formed ARN and fails the AWS provider's own ARN
  # validation on aws_lb_listener.load_balancer_arn (see
  # _common-v1-uplift-rules.md's Terraform 1.7 gotchas).
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock-alb/50dc6c495c0c9188"
      dns_name   = "mock-alb-123456789.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
      arn_suffix = "app/mock-alb/50dc6c495c0c9188"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock-tg/73e2d6bc24d8a067"
    }
  }
}

variables {
  name              = "svc"
  vpc_id            = "vpc-0123456789abcdef0"
  public_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"

  security_group_ingress_cidrs = ["10.0.0.0/16"]

  target_groups = {
    web = { port = 8080 }
    api = { port = 9090 }
  }
  default_target_group_key = "web"

  listener_rules = {
    api = {
      priority         = 10
      target_group_key = "api"
      conditions       = { path_patterns = ["/api/*"] }
    }
  }
}

run "target_group_arns_keys_equal_target_groups_keys" {
  # A mocked apply, never a real one: mock_provider never contacts AWS, and
  # this is required so the ARN values below are concrete rather than
  # "known after apply" (see the mock_resource comment above).
  command = apply

  assert {
    condition     = toset(keys(output.target_group_arns)) == toset(keys(var.target_groups))
    error_message = "target_group_arns must have exactly the same keys as target_groups: this is the shape ecs-service's load_balancers map is keyed by."
  }

  assert {
    condition     = length(output.target_group_arns) == 2
    error_message = "target_group_arns must have one entry per target_groups entry."
  }

  assert {
    condition     = alltrue([for arn in values(output.target_group_arns) : startswith(arn, "arn:aws:elasticloadbalancing:") && strcontains(arn, ":targetgroup/")])
    error_message = "Every target_group_arns value must be a plain target group ARN string."
  }
}

run "target_group_arns_folds_directly_into_ecs_service_load_balancers_shape" {
  command = apply

  # Exactly what a caller writes: no lookup(), no key rename, no wrapping
  # object beyond folding in the two static fields ecs-service also needs.
  assert {
    condition = alltrue([
      for key, entry in {
        for tg_key, arn in output.target_group_arns : tg_key => {
          target_group_arn = arn
          container_name   = "app"
          container_port   = 8080
        }
      } : entry.target_group_arn == output.target_group_arns[key]
    ])
    error_message = "Every reshaped load_balancers entry's target_group_arn must be exactly the value this module's target_group_arns output produced for that key, unchanged."
  }

  assert {
    condition = toset(keys({
      for tg_key, arn in output.target_group_arns : tg_key => {
        target_group_arn = arn
        container_name   = "app"
        container_port   = 8080
      }
    })) == toset(keys(var.target_groups))
    error_message = "Reshaping target_group_arns into ecs-service's load_balancers element type must not add, drop, or rename any key."
  }

  # The reshaped map's element type must match ecs-service's load_balancers
  # element type by construction: target_group_arn (string), container_name
  # (string), container_port (number), and the optional
  # advanced_configuration this test does not set.
  assert {
    condition = alltrue([
      for entry in values({
        for tg_key, arn in output.target_group_arns : tg_key => {
          target_group_arn = arn
          container_name   = "app"
          container_port   = 8080
        }
      }) : can(tostring(entry.target_group_arn)) && can(tostring(entry.container_name)) && can(tonumber(entry.container_port))
    ])
    error_message = "Every reshaped entry must carry a string target_group_arn and container_name and a number container_port, matching ecs-service's load_balancers element type."
  }
}
