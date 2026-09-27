variable "region" {
  description = "AWS region the ALB is created in."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "ALB name."
  type        = string
  default     = "internal-app"
}

variable "vpc_id" {
  description = "VPC to create the ALB in."
  type        = string
}

variable "private_subnet_ids" {
  description = "At least two subnets in different Availability Zones. Despite the module's public_subnet_ids input name, these are ordinary private subnets: internal = true means the ALB gets no public IP regardless of the subnets' own route tables."
  type        = set(string)
}

variable "vpc_cidr" {
  description = "CIDR block of vpc_id, used to scope security_group_ingress_cidrs to the VPC instead of the module's public 0.0.0.0/0 default."
  type        = string
}
