# One target group per target_groups entry. Keys drive the for_each and are
# the keys of the target_group_arns output (outputs.tf) — the interface
# contract with aws.modules.ecs-service's load_balancers input.

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = "${var.name}-${each.key}"
  port        = each.value.port
  protocol    = each.value.protocol
  target_type = each.value.target_type
  vpc_id      = var.vpc_id

  deregistration_delay = each.value.deregistration_delay

  health_check {
    enabled             = true
    protocol            = each.value.protocol
    path                = each.value.health_check.path
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    matcher             = each.value.health_check.matcher
  }

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length("${var.name}-${each.key}") <= 32
      error_message = "Target group name \"${var.name}-${each.key}\" is longer than the AWS limit of 32 characters; shorten name or the target_groups key \"${each.key}\"."
    }
  }
}
