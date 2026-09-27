# ALB with a WAFv2 web ACL

Otherwise identical to the minimal example, this associates a caller-supplied
REGIONAL-scope WAFv2 web ACL (`web_acl_arn`) with the ALB. This module never
creates or owns the web ACL: `web_acl_arn` is a plain ARN, the same
external-dependency pattern `aws.modules.ksm` and `aws.modules.state` use for
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
<!-- END_TF_DOCS -->
