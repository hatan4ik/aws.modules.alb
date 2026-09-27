# Path-based and host-based routing

Two target groups behind one ALB: `web` is the default action, and `api`
also gets its own `listener_rules` entries — one matching `/api/*` by path,
one matching `api.example.com` by host header. Both rules attach to the
HTTPS listener; a request that matches neither falls through to the default
action (`web`).

`target_group_arns` has one key per `target_groups` entry (`web` and `api`),
ready to fold into two separate `aws.modules.ecs-service` calls, one per
service, exactly as in the minimal example.

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
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN for the HTTPS listener, for example from aws.modules.acm's validated\_arn output. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | ALB name. | `string` | `"app"` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | At least two public subnets in different Availability Zones. | `set(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the ALB is created in. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC to create the ALB in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Plain ARN of each target group, keyed "web" and "api". Drop this straight into aws.modules.ecs-service's load\_balancers[*].target\_group\_arn. |
<!-- END_TF_DOCS -->
