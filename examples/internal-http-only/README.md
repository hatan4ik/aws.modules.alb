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
<!-- END_TF_DOCS -->
