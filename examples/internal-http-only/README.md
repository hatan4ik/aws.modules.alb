# Internal, HTTP-only ALB

The narrow case the brief and `docs/DESIGN.md` both warn is not a default
anyone should reach for: `internal = true` (no public IP, reachable only from
inside the VPC or a connected network) and `create_http_only = true` (no ACM
certificate, no HTTPS listener, plain HTTP forwarded directly to the target
group). It fits a documented internal-only need — for example a service that
already sits behind another TLS-terminating hop and only needs the ALB's own
health checks and target-group routing, never public HTTPS at this layer.

`security_group_ingress_cidrs` is deliberately scoped to the VPC's own CIDR
here, not the module's public `0.0.0.0/0` default: an internal, unencrypted
ALB must never be reachable from outside the VPC. `redirect_http_to_https`
has nothing to apply to in this mode and must stay at its default `true`; a
precondition rejects setting it to `false` here instead of silently ignoring
the override.

## Run

```sh
terraform init
terraform plan \
  -var vpc_id=vpc-0123456789abcdef0 \
  -var 'private_subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var vpc_cidr=10.0.0.0/16
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
| <a name="input_name"></a> [name](#input\_name) | ALB name. | `string` | `"internal-app"` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | At least two subnets in different Availability Zones. Despite the module's public\_subnet\_ids input name, these are ordinary private subnets: internal = true means the ALB gets no public IP regardless of the subnets' own route tables. | `set(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the ALB is created in. | `string` | `"us-east-1"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR block of vpc\_id, used to scope security\_group\_ingress\_cidrs to the VPC instead of the module's public 0.0.0.0/0 default. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC to create the ALB in. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | Internal DNS name of the ALB, resolvable only from inside the VPC (or peered/connected networks). |
| <a name="output_http_listener_arn"></a> [http\_listener\_arn](#output\_http\_listener\_arn) | ARN of the HTTP-only listener. https\_listener\_arn is null in this mode. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Plain ARN of the one target group, keyed "app". |
<!-- END_TF_DOCS -->
