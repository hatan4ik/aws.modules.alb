output "alb_dns_name" {
  description = "DNS name of the ALB. Feed alb_dns_name and alb_zone_id into an aws.modules.route53 alias record."
  value       = module.alb.alb_dns_name
}

output "target_group_arns" {
  description = "Plain ARN of the one target group, keyed \"app\". Drop this straight into aws.modules.ecs-service's load_balancers[*].target_group_arn."
  value       = module.alb.target_group_arns
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener."
  value       = module.alb.https_listener_arn
}
