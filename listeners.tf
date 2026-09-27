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

resource "aws_lb_listener" "http" {
  count = local.http_listener_enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

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
