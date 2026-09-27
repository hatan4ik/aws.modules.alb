# The HTTPS listener (when it exists) and the HTTP listener (when either the
# redirect or the http-only path is active). See docs/DESIGN.md, "HTTP
# listener existence is driven by redirect_http_to_https, not implied," for
# the three shapes these two resources render.

resource "aws_lb_listener" "https" {
  count = local.https_listener_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[var.default_target_group_key].arn
  }

  tags = local.tags
}

resource "aws_lb_listener_certificate" "additional" {
  for_each = local.https_listener_enabled ? var.additional_certificate_arns : []

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

# Trivy's AWS-0054 ("listener does not use HTTPS") correctly resolves the
# dynamic default_action blocks below and does not flag the default redirect
# shape at all; it flags only the genuine create_http_only = true case
# (examples/internal-http-only), which really does serve unencrypted HTTP.
# That is real and accepted, not a resolution artifact: docs/DESIGN.md
# documents it as the narrow, explicit escape hatch this brief calls for.
#trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
  count = local.http_listener_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # CKV_AWS_2 and CKV_AWS_103 flag every HTTP listener as not-HTTPS / not
  # TLS-1.2+, which is literally true of this resource's own protocol
  # attribute but misses what its default_action actually does. Checkov
  # cannot statically resolve which of the two dynamic "default_action"
  # blocks above is rendered (that depends on locals derived from
  # create_http_only / redirect_http_to_https), so it fires unconditionally
  # here.
  #
  # Verified: in the default shape (redirect_http_to_https = true, the
  # common case exercised by examples/minimal, examples/with-waf, and
  # examples/path-based-routing) this listener's only job is a 301 redirect
  # to the HTTPS listener — a false positive, not a real gap. Proven
  # directly by tests/listeners.tftest.hcl's
  # "https_with_redirect_is_the_default_shape" apply-based test, which
  # asserts aws_lb_listener.http[0].default_action[0].type == "redirect".
  #
  # In the explicit create_http_only = true mode (examples/internal-http-only,
  # tests/integration/smoke.tftest.hcl) this listener genuinely forwards
  # plain HTTP with no redirect. That is real, not a resolution artifact:
  # docs/DESIGN.md documents it as a narrow, explicit escape hatch for a
  # non-production ALB or one that already terminates TLS elsewhere, never
  # the module's default.
  #checkov:skip=CKV_AWS_2:See the comment above — false positive in the default redirect shape (tests/listeners.tftest.hcl), a real and documented deviation only in the explicit create_http_only mode (docs/DESIGN.md).
  #checkov:skip=CKV_AWS_103:Same HTTP listener as CKV_AWS_2 above; TLS does not apply to a plain-HTTP redirect or http-only listener by construction.
  # Exactly one of these two dynamic blocks ever emits an instance: this
  # listener only exists (local.http_listener_enabled) when either the
  # http-only path or the redirect path is active, never both.
  dynamic "default_action" {
    for_each = local.http_only_listener_enabled ? [1] : []

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this[var.default_target_group_key].arn
    }
  }

  dynamic "default_action" {
    for_each = local.http_redirect_listener_enabled ? [1] : []

    content {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = local.tags
}
