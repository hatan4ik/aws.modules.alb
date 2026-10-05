# The interface contract with aws.modules.ecs-service's BLUE_GREEN
# deployment strategy. target_group_arns (tests/target_group_arns.tftest.hcl)
# covers ROLLING; BLUE_GREEN additionally needs, on every load_balancers
# entry,
#
#   advanced_configuration = optional(object({
#     alternate_target_group_arn = string
#     production_listener_rule   = string
#     role_arn                   = string
#     test_listener_rule         = optional(string)
#   }))
#
# (read from hatan4ik/aws.modules.ecs-service's variables.tf on main), where
# production_listener_rule is a listener-RULE ARN: not a listener ARN, not a
# target group ARN. This module's listener_rule_arns output must be a
# map(string) keyed exactly like listener_rules, each value a listener-rule
# ARN, and an empty map (never null) when no rules are declared.

mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }

  # Deterministic, well-formed ARNs so command = apply resolves them to
  # concrete values instead of random filler (see target_group_arns.tftest.hcl
  # for why the mocked apply is needed).
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

  mock_resource "aws_lb_listener_rule" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/mock-alb/50dc6c495c0c9188/f2f7dc8efc522ab2/9683b2d02a6cabee"
    }
  }
}

variables {
  name              = "svc"
  vpc_id            = "vpc-0123456789abcdef0"
  public_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"

  security_group_ingress_cidrs = ["10.0.0.0/16"]

  # The blue/green pair: ecs-service registers tasks in "blue" and uses
  # "green" as the alternate target group.
  target_groups = {
    blue  = { port = 8080 }
    green = { port = 8080 }
  }
  default_target_group_key = "blue"
}

run "empty_map_when_no_listener_rules" {
  command = apply

  assert {
    condition     = output.listener_rule_arns != null && length(output.listener_rule_arns) == 0
    error_message = "listener_rule_arns must be an empty map, not null, when listener_rules is empty (its default)."
  }
}

run "one_entry_per_listener_rule_keyed_like_listener_rules" {
  command = apply

  variables {
    listener_rules = {
      prod = {
        priority         = 10
        target_group_key = "blue"
        conditions       = { path_patterns = ["/*"] }
      }
      test = {
        priority         = 20
        target_group_key = "blue"
        conditions       = { host_headers = ["test.example.com"] }
      }
    }
  }

  assert {
    condition     = toset(keys(output.listener_rule_arns)) == toset(keys(var.listener_rules))
    error_message = "listener_rule_arns must have exactly the same keys as listener_rules."
  }

  assert {
    condition     = alltrue([for key, arn in output.listener_rule_arns : arn == aws_lb_listener_rule.this[key].arn])
    error_message = "Every listener_rule_arns value must be exactly the ARN of the listener rule declared under the same key."
  }

  # Must be a listener-RULE ARN: ecs-service's production_listener_rule
  # rejects a listener ARN or a target group ARN at apply time.
  assert {
    condition = alltrue([
      for arn in values(output.listener_rule_arns) :
      startswith(arn, "arn:aws:elasticloadbalancing:") && strcontains(arn, ":listener-rule/") && !strcontains(arn, ":targetgroup/")
    ])
    error_message = "Every listener_rule_arns value must be a listener-rule ARN, not a listener or target group ARN."
  }
}

run "folds_directly_into_ecs_service_blue_green_advanced_configuration" {
  command = apply

  variables {
    listener_rules = {
      prod = {
        priority         = 10
        target_group_key = "blue"
        conditions       = { path_patterns = ["/*"] }
      }
    }
  }

  # Exactly what a caller writes for ecs-service's BLUE_GREEN strategy: one
  # load_balancers entry whose advanced_configuration takes the alternate
  # target group from target_group_arns and the production listener rule
  # from listener_rule_arns, with no lookup() and no ARN reconstruction.
  assert {
    condition = alltrue([
      for entry in values({
        app = {
          target_group_arn = output.target_group_arns["blue"]
          container_name   = "app"
          container_port   = 8080
          advanced_configuration = {
            alternate_target_group_arn = output.target_group_arns["green"]
            production_listener_rule   = output.listener_rule_arns["prod"]
            role_arn                   = "arn:aws:iam::123456789012:role/ecs-blue-green"
          }
        }
        }) : (
        can(tostring(entry.target_group_arn)) &&
        can(tostring(entry.advanced_configuration.alternate_target_group_arn)) &&
        entry.advanced_configuration.production_listener_rule == aws_lb_listener_rule.this["prod"].arn &&
        strcontains(entry.advanced_configuration.production_listener_rule, ":listener-rule/")
      )
    ])
    error_message = "A load_balancers entry built from target_group_arns and listener_rule_arns must carry the production listener rule's own listener-rule ARN, unchanged, in advanced_configuration.production_listener_rule."
  }
}
