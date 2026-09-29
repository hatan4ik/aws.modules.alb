# The one ALB this module call creates. create_http_only and certificate_arn
# are mutually exclusive-required (docs/DESIGN.md); every other listener and
# routing resource lives in listeners.tf and listener_rules.tf.

resource "aws_lb" "this" {
  # CKV2_AWS_20 ("ALB redirects HTTP requests into HTTPS ones") cannot see
  # into listeners.tf's aws_lb_listener.http dynamic "default_action" blocks
  # to confirm the redirect exists; it is a verified false positive in the
  # default shape (redirect_http_to_https = true, tests/listeners.tftest.hcl)
  # and a real, documented, explicit deviation only under create_http_only.
  # See the matching comment on aws_lb_listener.http in listeners.tf.
  #checkov:skip=CKV2_AWS_20:See the comment on aws_lb_listener.http in listeners.tf — false positive in the default redirect shape, real only in the explicit create_http_only mode (docs/DESIGN.md).
  name = var.name

  # AWS-0053 ("Load balancer is exposed publicly") is real, not a resolution
  # artifact, whenever internal = false: this module's whole reason for
  # existing, per ADR-0004, is the one deliberately public thing in the
  # workload path ("the public ALB subnets are the sole justified public
  # subnets"). A caller who genuinely needs an internal ALB sets internal =
  # true (examples/internal-http-only); the public default is intentional
  # and documented, not an oversight.
  #trivy:ignore:AWS-0053
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [module.security_group.id]
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
