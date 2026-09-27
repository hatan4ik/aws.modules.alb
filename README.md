# aws.modules.alb

Provisions one regional Application Load Balancer per module call: the ALB,
its security group, its target groups, its HTTPS and/or HTTP listener, and
any path/host-based listener rules beyond the default action. Per
[ADR-0004](/docs/adr/0004-edge-ingress-and-egress.md), this is the one
deliberately public thing in the whole workload path — everything behind it,
including the already-released `aws.modules.ecs-service`'s tasks, stays
private. `target_group_arns` is a `map(string)` keyed exactly like
`target_groups`, designed to fold directly into `ecs-service`'s
`load_balancers` input with no translation: that interface is this module's
whole reason for existing. Secure by default (HTTPS at the edge, egress
scoped to the VPC's own CIDR, deletion protection on), it creates nothing
beyond the ALB, its security group, its target groups, and its listeners.
Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

## Why this module

What you get from `vpc_id`, two subnets, a certificate, and one target
group, without setting anything else:

- HTTPS at the edge by default. `create_http_only` is off by default, so
  `certificate_arn` is required and every listener is TLS 1.2+
  (`ELBSecurityPolicy-TLS13-1-2-2021-06`); the HTTP listener on port 80 exists
  solely to 301-redirect to it. A caller with a genuine internal-only need
  can opt into HTTP-only explicitly — never the default.
- `target_group_arns` folds straight into `ecs-service`. Same keys as
  `target_groups`, plain ARN values: `{ for key, arn in
  module.alb.target_group_arns : key => { target_group_arn = arn,
  container_name = "app", container_port = 8080 } }` is the whole
  translation a caller writes, and `tests/target_group_arns.tftest.hcl`
  proves the key-shape contract directly.
- A security group scoped both ways. Ingress only on the listener ports that
  actually exist (443 and/or 80, never a port nothing is behind); egress
  scoped to the VPC's own CIDR, never `0.0.0.0/0`.
- Every external dependency is an identifier, not a submodule call.
  `web_acl_arn` (a REGIONAL WAFv2 web ACL, for example from
  `aws.modules.waf`) and `access_logs.bucket_name` (a bucket the caller
  already created and granted access to, for example via `aws.modules.s3`)
  are both plain inputs; this module never owns their lifecycle.
- Advisory, never blocking, posture checks: `deletion_protection_disabled`
  and `public_without_waf` warn on a plan without stopping it — a public ALB
  with no WAF might be exactly what you want, given another layer of
  protection.
- Plan-time validation of every input, including the cross-references a
  Terraform 1.7 variable validation cannot see on its own:
  `default_target_group_key` and every `listener_rules[*].target_group_key`
  must name a real `target_groups` entry, `create_http_only` and
  `certificate_arn` are exactly-one-path, listener rule priorities are
  unique.

## Quick start

```hcl
module "alb" {
  source = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>" # v1.0.0

  name              = "app"
  vpc_id            = "vpc-0123456789abcdef0"
  public_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  certificate_arn   = module.certificate.validated_arn # aws.modules.acm

  security_group_ingress_cidrs = ["0.0.0.0/0"]

  target_groups = {
    app = { port = 8080 }
  }
  default_target_group_key = "app"

  tags = { Environment = "prod", Owner = "platform" }
}

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

This creates one internet-facing ALB with a TLS 1.2+ HTTPS listener
forwarding to the `app` target group, a redirecting HTTP listener on port
80, a security group open on 443 and 80 to the world with egress scoped to
the VPC, and hands `ecs_service` the target group ARN it needs with no
lookup or key rename.

## Architecture

```text
root (one ALB)
├── alb.tf              aws_lb.this: the ALB, access logs, the http-only/certificate-arn XOR precondition
├── security_group.tf    aws_security_group.this (no inline rules), ingress/egress rules, the one documented data source (VPC CIDR)
├── target_groups.tf     aws_lb_target_group.this[*], one per target_groups entry
├── listeners.tf         aws_lb_listener.https[0] / .http[0], aws_lb_listener_certificate.additional[*]
├── listener_rules.tf    aws_lb_listener_rule.this[*], attached to whichever listener is primary
├── waf.tf               aws_wafv2_web_acl_association.this[0]
├── locals.tf            Listener-existence flags, tags, active security group ports
├── checks.tf             deletion_protection_disabled, public_without_waf (advisory)
└── outputs.tf            alb_arn, alb_dns_name, alb_zone_id, alb_arn_suffix, target_group_arns, security_group_id, https_listener_arn, http_listener_arn
```

Listener existence is driven entirely by `create_http_only` and
`redirect_http_to_https`:

| `create_http_only` | `redirect_http_to_https` | Result |
| --- | --- | --- |
| `false` (default) | `true` (default) | HTTPS listener forwards to targets; HTTP listener on 80 exists solely to redirect to it. |
| `false` | `false` | HTTPS listener only. No port 80 listener, so the security group never opens it. |
| `true` | must stay `true` (its default) | HTTP listener only, forwards directly to targets. `certificate_arn` must be unset. |

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | One target group, HTTPS with a redirecting HTTP listener, every other default. |
| [`examples/path-based-routing`](examples/path-based-routing) | Two target groups, one routed by `listener_rules` on both a path pattern and a host header. |
| [`examples/with-waf`](examples/with-waf) | Associating a caller-supplied REGIONAL WAFv2 web ACL through `web_acl_arn`. |
| [`examples/internal-http-only`](examples/internal-http-only) | The narrow `internal = true` + `create_http_only = true` case, scoped to the VPC's own CIDR. |

## Security model

Edge

- HTTPS is the default path: `certificate_arn` is required unless
  `create_http_only = true`, and the HTTPS listener always sets
  `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`. The HTTP-only path is
  a narrow, explicit escape hatch, never the default, and rejects
  `additional_certificate_arns` and any override of `redirect_http_to_https`
  as not applicable.
- `deletion_protection` and `drop_invalid_header_fields` both default to
  `true`; a `check` warns, advisory only, when deletion protection is
  turned off.

Security group

- No inline rules on `aws_security_group.this`: AWS's own default
  allow-all-egress rule is revoked at creation, and the module adds back
  exactly the rules it intends.
- Ingress (`aws_vpc_security_group_ingress_rule`) is scoped to exactly the
  listener ports that exist (443 and/or 80) and the CIDRs in
  `security_group_ingress_cidrs`, which has no silent empty default: a
  caller must set it explicitly, even to keep the public
  `["0.0.0.0/0"]` default.
- Egress (`aws_vpc_security_group_egress_rule`) is scoped to the VPC's own
  CIDR, read from the one documented data source in this module
  (`data.aws_vpc.this`, keyed by `var.vpc_id`) — see
  [docs/DESIGN.md](docs/DESIGN.md) for why this is the sole exception to
  "no data sources."
- `public_without_waf` warns, advisory only, when
  `security_group_ingress_cidrs` includes `0.0.0.0/0` and `web_acl_arn` is
  null. A legitimate caller may have another reason (an upstream Global
  Accelerator shield, for example) not to attach one.

Not created here

- The WAFv2 web ACL (`web_acl_arn` is a plain ARN, for example from
  `aws.modules.waf`), the access log bucket and its policy
  (`access_logs.bucket_name`, for example from `aws.modules.s3`), any Route
  53 record (`alb_dns_name`/`alb_zone_id` feed `aws.modules.route53`), and
  target registration itself (`aws.modules.ecs-service`'s `load_balancers`
  registers targets against the ARNs this module hands back).

## Lifecycle notes

- `aws_security_group.this` and every `aws_lb_target_group.this` entry use
  `create_before_destroy = true`, so a change that would otherwise conflict
  (a target group's `port` or `protocol`, for example) creates the
  replacement before the old one is destroyed.
- Target group and listener rule keys drive their `for_each`, so adding a
  `target_groups` or `listener_rules` entry adds exactly one resource
  instance and removing one removes exactly one.
- Changing `create_http_only` or `redirect_http_to_https` changes which
  listener resources exist (`aws_lb_listener.https[0]` / `.http[0]`), which
  changes `https_listener_arn` / `http_listener_arn` and the active
  ingress ports in the same apply.
- Two advisory `check` blocks warn without blocking:
  `deletion_protection_disabled` and `public_without_waf`.

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use
  `mock_provider`: no credentials, nothing created. Plan-only runs cover
  defaults, every validation and precondition, and both advisory checks;
  apply-only runs (`tests/listeners.tftest.hcl`,
  `tests/listener_rules.tftest.hcl`, `tests/target_group_arns.tftest.hcl`)
  cover behaviour that depends on a resolved ARN, pinned to a deterministic
  value with `mock_resource` defaults rather than random per-apply filler.
  `tests/target_group_arns.tftest.hcl` is the interface-contract test: it
  asserts the output map's keys equal `target_groups`'s keys, then reshapes
  the output exactly as a caller would into `ecs-service`'s
  `load_balancers` element type.
- **Integration suite** (`tests/integration/`, run by `make
  integration-smoke` or the dispatch-only `integration` workflow) applies
  the module for real in **your** account against a disposable VPC fixture:
  one HTTP-only ALB with one target group (avoiding the need for a real ACM
  certificate), asserted against the real API, then destroyed. See
  [tests/integration/README.md](tests/integration/README.md) for
  permissions and the GitHub environment contract.

## Design principles

- Single responsibility. One ALB, its own security group, its own target
  groups and listeners. No target registration, no WAF web ACL, no DNS
  record, no log bucket — each belongs to a sibling module or the caller.
- Open/closed. New target groups and listener rules arrive as map entries;
  no branch of the module needs editing to add a path-based route.
- Liskov substitution. `target_group_arns[key]` means the same thing
  regardless of how many target groups exist: the plain ARN of the target
  group keyed `key`.
- Interface segregation. WAF, access logs, additional certificates, and
  listener rules all stay at a safe default until declared.
- Dependency inversion. `web_acl_arn` and `access_logs.bucket_name` are
  identifiers, never module calls this module owns; the one data source it
  has reads an attribute of an ID the caller already gave it.

The full rationale, including the interface contract with `ecs-service` and
why the VPC CIDR data source exists, is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- One regional ALB per module call, in the provider's own region.
- Out of scope for v1: target group attachment (that is `ecs-service`'s
  job), fixed-response and authenticate-oidc/authenticate-cognito listener
  actions (only forward and redirect), and cross-zone load balancing /
  connection draining tuning beyond `deregistration_delay` (left at the AWS
  default). See [docs/DESIGN.md](docs/DESIGN.md), "Out of scope for v1."

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the
major version, new optional inputs and outputs bump the minor version, fixes
bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment,
so the source cannot move under you:

```hcl
module "alb" {
  source = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only
from a GitHub-verified, signed, annotated semantic-version tag that points
at the merged `main` revision; lightweight or unsigned tags are rejected
before anything is published. With a GitHub-associated GPG or SSH signing
key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag
points at the revision it checked out, and a maintenance release for an
older line is cut from that line's commit.

All changes are listed in [CHANGELOG.md](CHANGELOG.md). This is a brand new
module: there is no prior version and no `docs/UPGRADE-1.0.md`.

## Contributing

Development setup, the local quality gate, the test-first workflow, and the
release process are described in [CONTRIBUTING.md](CONTRIBUTING.md).
Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
