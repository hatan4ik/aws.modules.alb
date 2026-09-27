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
<!-- END_TF_DOCS -->
