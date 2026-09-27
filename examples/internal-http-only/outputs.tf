output "alb_dns_name" {
  description = "Internal DNS name of the ALB, resolvable only from inside the VPC (or peered/connected networks)."
  value       = module.alb.alb_dns_name
}

output "http_listener_arn" {
  description = "ARN of the HTTP-only listener. https_listener_arn is null in this mode."
  value       = module.alb.http_listener_arn
}

output "target_group_arns" {
  description = "Plain ARN of the one target group, keyed \"app\"."
  value       = module.alb.target_group_arns
}
