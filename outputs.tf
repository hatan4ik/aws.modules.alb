output "alb_arn" {
  description = "ARN of the ALB."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB, for an alias record through aws.modules.route53."
  value       = aws_lb.this.zone_id
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB, needed by CloudWatch metrics and by aws.modules.global-accelerator's health checks."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arns" {
  description = "Plain ARN of each target group, keyed by the same keys as the target_groups input. Drop this straight into aws.modules.ecs-service's load_balancers[*].target_group_arn with no translation: this is the module's interface contract with ecs-service, proved in tests/target_group_arns.tftest.hcl."
  value       = { for key, tg in aws_lb_target_group.this : key => tg.arn }
}

output "security_group_id" {
  description = "ID of the ALB's security group."
  value       = module.security_group.id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener, or null when create_http_only = true and no HTTPS listener exists."
  value       = local.https_listener_enabled ? aws_lb_listener.https[0].arn : null
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener (redirect or http-only), or null when redirect_http_to_https = false and create_http_only = false, in which case no port 80 listener exists."
  value       = local.http_listener_enabled ? aws_lb_listener.http[0].arn : null
}
