# Minimal ALB

The smallest working call of `aws.modules.alb`: one public, internet-facing
ALB with one target group, serving HTTPS from `certificate_arn` with a
redirecting HTTP listener on port 80 — every other input at its secure
default (`deletion_protection = true`, `drop_invalid_header_fields = true`,
egress scoped to the VPC CIDR). Start here before adding path-based routing,
a WAF association, or the narrow HTTP-only case.

`certificate_arn` is a placeholder ARN in the examples below; in a real call
it comes from a validated `aws.modules.acm` certificate (its `validated_arn`
output). `target_group_arns` is what you fold into
`aws.modules.ecs-service`'s `load_balancers` input:

```hcl
module "ecs_service" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git?ref=<commit-sha>" # v1.0.0

  # ...

  load_balancers = {
    for key, arn in module.alb.target_group_arns : key => {
      target_group_arn = arn
      container_name    = "app"
      container_port    = 8080
    }
  }
}
```

## Run

```sh
terraform init
terraform plan \
  -var vpc_id=vpc-0123456789abcdef0 \
  -var 'public_subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var certificate_arn=arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111
```

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
