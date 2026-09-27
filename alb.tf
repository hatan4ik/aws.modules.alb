# The one ALB this module call creates. create_http_only and certificate_arn
# are mutually exclusive-required (docs/DESIGN.md); every other listener and
# routing resource lives in listeners.tf and listener_rules.tf.

resource "aws_lb" "this" {
  name               = var.name
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this.id]
  subnets            = local.public_subnet_ids

  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = var.drop_invalid_header_fields

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : [var.access_logs]

    content {
      bucket  = access_logs.value.bucket_name
      prefix  = access_logs.value.prefix
      enabled = true
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.create_http_only != (var.certificate_arn != null)
      error_message = "Set exactly one: create_http_only = true for the HTTP-only path (leave certificate_arn unset), or certificate_arn for the default HTTPS path (leave create_http_only at its default false)."
    }

    precondition {
      condition     = !var.create_http_only || length(var.additional_certificate_arns) == 0
      error_message = "additional_certificate_arns applies to the HTTPS listener only and must be empty when create_http_only = true, since there is then no HTTPS listener to attach them to."
    }

    precondition {
      condition     = !var.create_http_only || var.redirect_http_to_https == true
      error_message = "redirect_http_to_https is not applicable when create_http_only = true: there is no HTTPS listener to redirect to. Leave it at its default (true) or remove the override."
    }

    precondition {
      condition     = contains(keys(var.target_groups), var.default_target_group_key)
      error_message = "default_target_group_key \"${var.default_target_group_key}\" must reference a key declared in target_groups (${join(", ", keys(var.target_groups))})."
    }
  }
}
