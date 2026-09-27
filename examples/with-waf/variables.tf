variable "region" {
  description = "AWS region the ALB is created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "ALB name."
  type        = string
  default     = "app"
}

variable "vpc_id" {
  description = "VPC to create the ALB in."
  type        = string
}

variable "public_subnet_ids" {
  description = "At least two public subnets in different Availability Zones."
  type        = set(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener, for example from aws.modules.acm's validated_arn output."
  type        = string
}

variable "web_acl_arn" {
  description = "ARN of a REGIONAL-scope WAFv2 web ACL, for example from aws.modules.waf, to associate with the ALB."
  type        = string
}
