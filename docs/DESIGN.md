# Design: aws.modules.alb v1

Status: accepted 2026-09-27. Brand new module: no v0.x baseline, no live consumer, no `docs/UPGRADE-1.0.md`.

## Purpose

`aws.modules.alb` provisions **one** regional Application Load Balancer per
module call: the ALB itself, its security group, its target groups, its
HTTPS and/or HTTP listener, and any path/host-based listener rules beyond the
default action.

It exists to implement [ADR-0004](/docs/adr/0004-edge-ingress-and-egress.md):
"the public ALB subnets are the sole justified public subnets... ALB targets,
Fargate tasks, databases, and caches are private." This module is the one
deliberately public thing in the whole workload path. Everything behind it —
the already-released `aws.modules.ecs-service`'s tasks, databases, caches —
stays private, and this module's whole reason for existing is to hand that
service module exactly the target group ARNs it needs, in exactly the shape
it already expects, with no translation layer in between.

## The interface contract with `aws.modules.ecs-service`

`aws.modules.ecs-service` v1.0.0's `load_balancers` input is:

```hcl
variable "load_balancers" {
  type = map(object({
    target_group_arn = string
    container_name    = string
    container_port    = number
    advanced_configuration = optional(object({ ... }))
  }))
  default  = {}
  nullable = false
}
```

This module's `target_group_arns` output is a `map(string)` with **the same
keys as the `target_groups` input**, each value the plain ARN string. A
caller composes the two directly:

```hcl
load_balancers = {
  for key, arn in module.alb.target_group_arns : key => {
    target_group_arn = arn
    container_name    = "app"
    container_port    = 8080
  }
}
```

No `lookup()`, no key renaming, no wrapping object. `target_group_arns`
IS the map a caller folds a couple of static fields into. This is proven
directly in `tests/target_group_arns.tftest.hcl`, which asserts
`keys(output.target_group_arns) == keys(var.target_groups)` and then re-shapes
the output exactly as a caller would, into an object matching
`ecs-service`'s `load_balancers` element type, and asserts that reshaped
value's field names against that type by construction.

## What this module deliberately does not do

- **No submodule call to `aws.modules.waf`.** `web_acl_arn` is a plain string
  input, validated to look like a REGIONAL WAFv2 web ACL ARN. Same pattern as
  `aws.modules.ksm` and `aws.modules.state` consuming external identifiers:
  every external dependency is an ARN or ID the caller passes in, never a
  module call this module owns the lifecycle of.
- **No S3 bucket for access logs.** `access_logs` takes a `bucket_name` (and
  optional `prefix`) the caller already created and owns — for example
  through `aws.modules.s3` — and has already granted the regional ELB
  log-delivery service account `s3:PutObject` on through that bucket's
  policy. This module only points the ALB at the bucket; it does not create,
  encrypt, or write a policy for it. Getting that policy wrong is a common
  cause of silent access-log delivery failure, and it is the bucket owner's
  responsibility, not this module's.
- **No Route 53 records.** `alb_dns_name` and `alb_zone_id` are exposed for a
  caller to feed into `aws.modules.route53`'s alias record input; this module
  never creates a hosted zone record itself.
- **No listener rules on a listener that does not exist.** Rules always
  attach to whichever listener actually serves traffic: the HTTPS listener
  when one exists, otherwise the HTTP-only listener. There is exactly one
  "primary" listener per module call, by construction.

## Key design decisions

### HTTP listener existence is driven by `redirect_http_to_https`, not implied

Three shapes are possible, chosen entirely by `create_http_only` and
`redirect_http_to_https`:

| `create_http_only` | `redirect_http_to_https` | Result |
| --- | --- | --- |
| `false` (default) | `true` (default) | HTTPS listener forwards to targets; HTTP listener on 80 exists solely to 301-redirect to HTTPS. The security default: encrypted at the edge, with a courteous redirect for anyone who lands on port 80. |
| `false` | `false` | HTTPS listener only. No port 80 listener at all, so the security group never opens port 80. For a caller who terminates TLS upstream (for example behind CloudFront/Global Accelerator's own TLS) and never wants an unencrypted listener, not even a redirect. |
| `true` | must stay `true` (its default) | HTTP listener only, forwards directly to targets. `certificate_arn` must be unset. `redirect_http_to_https` has nothing to redirect to in this mode, so a caller who explicitly sets it to `false` here is telling the module something that cannot be true; it is rejected at plan time rather than silently ignored, the same "reject in the mode it doesn't apply" rule as `aws.modules.acm`'s per-mode options. |

`create_http_only = true` and `certificate_arn` set are mutually
exclusive-required: a precondition on `aws_lb.this` enforces the XOR
directly, with a message naming both settings.

### The security group's egress needs the VPC's CIDR, which is not an input

The brief requires "egress to the VPC CIDR only — do not default to
unrestricted egress," but the interface takes only `vpc_id`, not a CIDR
block. Every other module this session avoids data sources except for
partition/region/account, which the provider already knows. A VPC's CIDR is
none of those, but there is no sound way to scope egress to "the VPC" from an
ID alone without either reading it or asking the caller to repeat information
AWS already has. This module reads it with one `data "aws_vpc"` keyed by
`var.vpc_id` — the smallest possible data source, one attribute
(`cidr_block`), no filtering, no lookup ambiguity — and documents the
deviation here rather than silently exceeding the "no data sources" rule.
Contract tests mock it with `mock_data "aws_vpc" { defaults = { cidr_block =
"10.0.0.0/16" } }` under Terraform 1.7's mock-provider data mocking, so the
suite stays credential-free.

### Ingress is scoped to listener ports that actually exist, not a fixed 80+443

`security_group_ingress_cidrs` opens only the ports the module actually
listens on: 443 when an HTTPS listener exists, 80 when an HTTP listener
exists (redirect or http-only), never a port with nothing behind it. Rules
are `aws_vpc_security_group_ingress_rule` resources, one per (port, CIDR)
pair, each with its own description — not a monolithic inline CIDR list —
so a plan shows exactly which rule a CIDR change would touch.

### Target group and listener rule cross-references are preconditions, not variable validations

Terraform 1.7 only allows a variable's own `validation` block to reference
that variable itself; cross-variable rules (`default_target_group_key` must
be a `target_groups` key, every `listener_rules[*].target_group_key` too,
`additional_certificate_arns` must be empty when `create_http_only = true`)
are `precondition` blocks on the resources that actually consume the
cross-reference (`aws_lb.this`, `aws_lb_listener.https`/`.http`,
`aws_lb_listener_rule.this`), the same pattern `aws.modules.acm` uses for its
per-mode rules in `certificate.tf`.

## Architecture

```text
root (one ALB)
├── variables.tf        Inputs grouped by concern: identity/network, listener/TLS, WAF, access logs, security group, target groups, listener rules, tags.
├── locals.tf            Listener-existence flags, tags, the security group's active ports, target group name derivation.
├── security_group.tf    aws_security_group.this (no inline rules), aws_vpc_security_group_ingress_rule.listener[*], aws_vpc_security_group_egress_rule.vpc, data.aws_vpc.this (VPC CIDR only).
├── target_groups.tf     aws_lb_target_group.this[*], one per target_groups entry, name-length precondition.
├── alb.tf               aws_lb.this: the ALB, access logs, the http-only/certificate-arn XOR precondition.
├── listeners.tf         aws_lb_listener.https[0], aws_lb_listener.http[0], aws_lb_listener_certificate.additional[*] (SNI).
├── listener_rules.tf    aws_lb_listener_rule.this[*], attached to whichever listener is primary.
├── waf.tf               aws_wafv2_web_acl_association.this[0], only when web_acl_arn is set.
├── checks.tf             Advisory checks: deletion_protection_disabled, public_without_waf.
└── outputs.tf            alb_arn, alb_dns_name, alb_zone_id, alb_arn_suffix, target_group_arns, security_group_id, https_listener_arn, http_listener_arn.
```

## Principles and how the module applies them

- **Single responsibility.** One ALB, its own security group, its own
  target groups and listeners. No target registration (that is
  `aws.modules.ecs-service`'s job through `load_balancers`), no WAF web ACL
  (that is `aws.modules.waf`'s job), no DNS record (that is
  `aws.modules.route53`'s job), no log bucket (that is the caller's, often
  via `aws.modules.s3`).
- **Open/closed.** New target groups and listener rules arrive as map
  entries; no branch of the module needs editing to add a path-based route.
- **Liskov substitution.** `target_group_arns[key]` means the same thing
  regardless of how many target groups exist or what routes to them: the
  plain ARN of the target group keyed `key`, directly assignable into
  `ecs-service`'s `load_balancers[key].target_group_arn`.
- **Interface segregation.** A caller who wants only the default HTTPS path
  sets `name`, `vpc_id`, `public_subnet_ids`, `certificate_arn`, and one
  `target_groups` entry plus `default_target_group_key`; every other input
  (WAF, access logs, additional certificates, listener rules) stays at a
  safe default until declared.
- **Dependency inversion.** `web_acl_arn` and `access_logs.bucket_name` are
  identifiers, never module calls this module owns; `certificate_arn` is
  produced elsewhere (for example `aws.modules.acm`) and consumed as an ARN.
  The one data source this module has (`aws_vpc`, see above) is the sole,
  documented exception, and it reads an attribute of an ID the caller
  already gave it — never a lookup that could resolve ambiguously.
- **Clean, deterministic code.** Subnets and CIDR-derived security group
  rules are sorted before use, target group and listener rule keys drive
  every `for_each`, and every cross-input rule is a precondition with a
  message that names the fix.

## Security defaults

- HTTPS at the edge by default: `create_http_only = false`, `certificate_arn`
  required in that mode, `redirect_http_to_https = true` sends anything on
  port 80 straight to port 443.
- `deletion_protection = true` and `drop_invalid_header_fields = true` by
  default; a `check` block warns (never blocks) when deletion protection is
  turned off.
- The security group's egress is scoped to the VPC's own CIDR, never
  `0.0.0.0/0`; ingress is scoped to exactly the listener ports that exist.
- `security_group_ingress_cidrs` has no empty default: a caller must set it
  explicitly, even to keep the documented `["0.0.0.0/0"]` public default, so
  an ALB can never be silently made unreachable nor silently left with an
  unreviewed CIDR list.
- A `check` block (`public_without_waf`) warns, advisory only, when the
  security group allows `0.0.0.0/0` and no `web_acl_arn` is set — a
  legitimate caller may have another reason (Global Accelerator's own
  protections, an upstream WAF) so this never blocks the plan.
- The TLS listener's `ssl_policy` defaults to a TLS 1.2+ ELB security policy;
  no listener is ever created with the AWS default (which is `null`/no
  minimum) left unset.

## Testing strategy

- Contract tests use `mock_provider "aws" {}` with `command = plan`; the one
  data source is covered with `mock_data "aws_vpc" { defaults = { cidr_block
  = "10.0.0.0/16" } }`. No credentials.
- `tests/target_group_arns.tftest.hcl` is the interface-contract test: it
  asserts the output map's keys equal the input map's keys, then reshapes the
  output into the exact object shape `ecs-service`'s `load_balancers`
  element type expects and asserts that shape holds.
- `tests/validation.tftest.hcl` exercises every variable validation and
  precondition with `expect_failures`, paired with a passing run for each
  rule.
- `tests/listeners.tftest.hcl` covers the HTTPS/HTTP-only/redirect matrix;
  `tests/listener_rules.tftest.hcl` covers path- and host-based routing and
  priority uniqueness; `tests/waf.tftest.hcl` and `tests/access_logs.tftest.hcl`
  cover those features on and off; `tests/checks.tftest.hcl` covers both
  advisory checks.
- Every example is initialized, validated, linted, and scanned in CI, and the
  credential-driven `tests/integration/smoke.tftest.hcl` proves a real HTTP-only
  ALB with one target group against a disposable VPC fixture, then destroys
  everything. It needs no ACM certificate, which would otherwise require a
  validated domain this suite does not have.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0`.
- AWS provider `>= 6.35.0, < 7.0.0`.
- One regional ALB per module call, in the provider's own region.

## Out of scope for v1

- Target group attachment (`aws_lb_target_group_attachment`): registration
  is `aws.modules.ecs-service`'s job through `load_balancers`; this module
  only creates the target groups and hands back their ARNs.
- Fixed-response and authenticate-oidc/authenticate-cognito listener actions:
  only forward (default action, listener rules) and redirect (the HTTP →
  HTTPS default) are supported. A caller with an auth requirement composes it
  outside the module today; a future minor version can add it as another
  optional action shape without breaking this interface.
- Cross-zone load balancing and connection draining beyond
  `deregistration_delay` are left at the AWS default (both enabled) since the
  brief does not ask for them and the AWS defaults are already the
  recommended posture.
