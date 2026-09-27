# Path- and host-based routing beyond the default action, attached to
# whichever listener actually serves traffic (locals.primary_listener_arn).

resource "aws_lb_listener_rule" "this" {
  for_each = var.listener_rules

  listener_arn = local.primary_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }

  dynamic "condition" {
    for_each = each.value.conditions.path_patterns == null ? [] : [each.value.conditions.path_patterns]

    content {
      path_pattern {
        values = tolist(condition.value)
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.conditions.host_headers == null ? [] : [each.value.conditions.host_headers]

    content {
      host_header {
        values = tolist(condition.value)
      }
    }
  }

  lifecycle {
    precondition {
      condition     = contains(keys(var.target_groups), each.value.target_group_key)
      error_message = "listener_rules[\"${each.key}\"].target_group_key \"${each.value.target_group_key}\" must reference a key declared in target_groups (${join(", ", keys(var.target_groups))})."
    }
  }
}
