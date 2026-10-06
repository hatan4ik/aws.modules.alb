# ALB with a WAFv2 web ACL

Otherwise identical to the minimal example, this associates a caller-supplied
REGIONAL-scope WAFv2 web ACL (`web_acl_arn`) with the ALB. This module never
creates or owns the web ACL: `web_acl_arn` is a plain ARN, the same
external-dependency pattern `aws.modules.kms` and `aws.modules.state` use for
identifiers they consume rather than manage. Pass the `arn` output of a
`aws.modules.waf` call (or any other REGIONAL web ACL) here, and the advisory
`public_without_waf` check no longer fires for a public ALB.

## Run

```sh
terraform init
terraform plan \
  -var vpc_id=vpc-0123456789abcdef0 \
  -var 'public_subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var certificate_arn=arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111 \
  -var web_acl_arn=arn:aws:wafv2:us-east-1:123456789012:regional/webacl/example/11111111-1111-1111-1111-111111111111
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
| <a name="input_web_acl_arn"></a> [web\_acl\_arn](#input\_web\_acl\_arn) | ARN of a REGIONAL-scope WAFv2 web ACL, for example from aws.modules.waf, to associate with the ALB. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Plain ARN of the one target group, keyed "app". |
<!-- END_TF_DOCS -->
