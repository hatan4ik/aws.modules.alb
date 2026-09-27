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
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_alb"></a> [alb](#module\_alb) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN for the HTTPS listener, for example from aws.modules.acm's validated\_arn output. This example only carries the placeholder through; it does not request a certificate itself. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ALB name. | `string` | `"app"` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | At least two public subnets in different Availability Zones. | `set(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the ALB is created in. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC to create the ALB in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB. Feed alb\_dns\_name and alb\_zone\_id into an aws.modules.route53 alias record. |
| <a name="output_https_listener_arn"></a> [https\_listener\_arn](#output\_https\_listener\_arn) | ARN of the HTTPS listener. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Plain ARN of the one target group, keyed "app". Drop this straight into aws.modules.ecs-service's load\_balancers[*].target\_group\_arn. |
<!-- END_TF_DOCS -->
