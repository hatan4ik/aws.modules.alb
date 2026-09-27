output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = module.alb.alb_dns_name
}

output "target_group_arns" {
  description = "Plain ARN of the one target group, keyed \"app\"."
  value       = module.alb.target_group_arns
}
