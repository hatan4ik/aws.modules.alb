output "name" {
  description = "Disposable resource name prefix, including the random suffix."
  value       = local.name
}

output "vpc_id" {
  description = "Disposable VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the disposable VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the two disposable public subnets."
  value       = aws_subnet.public[*].id
}

output "tags" {
  description = "Tags applied to every disposable resource, for reuse on the module under test."
  value       = local.tags
}
