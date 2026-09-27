output "alb_dns_name" {
  description = "DNS name of the ALB."
  value       = module.alb.alb_dns_name
}

output "target_group_arns" {
  description = "Plain ARN of each target group, keyed \"web\" and \"api\". Drop this straight into aws.modules.ecs-service's load_balancers[*].target_group_arn."
  value       = module.alb.target_group_arns
}
