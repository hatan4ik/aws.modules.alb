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

- The security group (`module.security_group.aws_security_group.this_cbd[0]`)
  and every `aws_lb_target_group.this` entry use `create_before_destroy =
  true`, so a change that would otherwise conflict (a target group's `port`
  or `protocol`, or the security group's description, for example) creates
  the replacement before the old one is destroyed. The security group's AWS
  name is generated from `name_prefix = "<name>-alb-"` (known only after
  apply) so the replacement never collides with the old group's name; its
  `Name` tag stays `<name>-alb`. Use `security_group_id` or the tag, never
  the group name, to refer to it.
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
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_security_group"></a> [security\_group](#module\_security\_group) | git::https://github.com/hatan4ik/aws.modules.security-group.git | 390733e8c1d6656fbc8092e7fd1b0b6e1eac6e13 |

## Resources

| Name | Type |
|------|------|
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_certificate.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_certificate) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_wafv2_web_acl_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_logs"></a> [access\_logs](#input\_access\_logs) | Access log destination the caller already created and owns (for example through aws.modules.s3), and has already granted the regional ELB log-delivery service account permission to write to via that bucket's policy. This module only points the ALB at bucket\_name (and optional prefix); it does not create the bucket or write its policy. null (default) leaves access logging off. | <pre>object({<br/>    bucket_name = string<br/>    prefix      = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_additional_certificate_arns"></a> [additional\_certificate\_arns](#input\_additional\_certificate\_arns) | Further ACM certificate ARNs attached to the HTTPS listener for SNI. Must be empty when create\_http\_only = true, since there is then no HTTPS listener to attach them to. | `set(string)` | `[]` | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN for the HTTPS listener, for example from the already-released aws.modules.acm. Required unless create\_http\_only = true, and must be left unset when it is (a precondition on the ALB enforces this exactly-one-path rule). | `string` | `null` | no |
| <a name="input_create_http_only"></a> [create\_http\_only](#input\_create\_http\_only) | false (default) serves HTTPS from certificate\_arn, per ADR-0004's "HTTPS at the edge" decision. true skips the HTTPS listener entirely and serves plain HTTP only: a narrow escape hatch for a non-production ALB or one that sits behind something that already terminates TLS (for example a CloudFront or Global Accelerator hop that re-encrypts elsewhere) — never a default anyone should reach for. Mutually exclusive-required with certificate\_arn: exactly one of the two paths is valid, enforced by a precondition on the ALB. | `bool` | `false` | no |
| <a name="input_default_target_group_key"></a> [default\_target\_group\_key](#input\_default\_target\_group\_key) | target\_groups key the HTTPS (or HTTP-only) listener's default action forwards to. Must reference a real target\_groups key; enforced by a precondition on the listener, since a variable validation cannot see another variable's value under Terraform 1.7. | `string` | n/a | yes |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | true (default) blocks the ALB from being deleted until it is turned off. A check block warns, advisory only, when this is false. | `bool` | `true` | no |
| <a name="input_drop_invalid_header_fields"></a> [drop\_invalid\_header\_fields](#input\_drop\_invalid\_header\_fields) | true (default) drops HTTP requests with invalid header fields, an AWS security best practice. This module is secure by default. | `bool` | `true` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | Seconds the ALB keeps an idle connection open, 1-4000. | `number` | `60` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | false (default) creates an internet-facing ALB in public\_subnet\_ids, which is this module's whole purpose per ADR-0004. Set true only for a documented internal-only need; public\_subnet\_ids still names the subnets the ALB's network interfaces are created in. | `bool` | `false` | no |
| <a name="input_listener_rules"></a> [listener\_rules](#input\_listener\_rules) | Path- or host-based routing rules beyond the default action, keyed by a short rule name. Each rule's target\_group\_key must reference a target\_groups key (enforced by a precondition, not a variable validation, for the same cross-variable reason as default\_target\_group\_key) and each rule needs at least one of conditions.path\_patterns or conditions.host\_headers. Rules attach to whichever listener actually serves traffic: HTTPS when it exists, otherwise the HTTP-only listener. Empty by default; the listener's default action alone then handles every request. | <pre>map(object({<br/>    priority         = number<br/>    target_group_key = string<br/>    conditions = object({<br/>      path_patterns = optional(set(string))<br/>      host_headers  = optional(set(string))<br/>    })<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the ALB. AWS caps load balancer names at 32 characters, alphanumeric and hyphens, must not start or end with a hyphen, and must not start with "internal-" (an AWS-reserved prefix regardless of the internal input). Also used to derive the security group name and every target group name (name-<key>), so keep it short enough to leave room for your longest target\_groups key. | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Subnets the ALB's network interfaces are created in, at least two in different Availability Zones. Named for this module's normal internet-facing case (ADR-0004); still the subnet set to use when internal = true. | `set(string)` | n/a | yes |
| <a name="input_redirect_http_to_https"></a> [redirect\_http\_to\_https](#input\_redirect\_http\_to\_https) | true (default) creates an HTTP listener on port 80 whose only job is a 301 redirect to the HTTPS listener; false creates no port 80 listener at all, so the security group never opens it. Not applicable when create\_http\_only = true (there is no HTTPS listener to redirect to); a precondition rejects setting it to anything but its default true in that mode instead of silently ignoring the override. | `bool` | `true` | no |
| <a name="input_security_group_ingress_cidrs"></a> [security\_group\_ingress\_cidrs](#input\_security\_group\_ingress\_cidrs) | CIDRs allowed to reach the ALB's active listener ports (443 when HTTPS exists, 80 when an HTTP listener exists). Defaults to ["0.0.0.0/0"] since a public ALB is the point (ADR-0004), but must be set explicitly and non-empty: this module never silently defaults to an empty set that would make the ALB unreachable. | `set(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource the module creates. The module adds a Name tag and never overrides caller tags. | `map(string)` | `{}` | no |
| <a name="input_target_groups"></a> [target\_groups](#input\_target\_groups) | Target groups keyed by a short logical name, for example "app" or "api". These keys are also the keys of the target\_group\_arns output, so a caller folds that output straight into aws.modules.ecs-service's load\_balancers map. target\_type defaults to "ip", correct for Fargate awsvpc mode. At least one entry is required: an ALB with no target groups is meaningless. | <pre>map(object({<br/>    port        = number<br/>    protocol    = optional(string, "HTTP")<br/>    target_type = optional(string, "ip")<br/>    health_check = optional(object({<br/>      path                = optional(string, "/")<br/>      interval            = optional(number, 30)<br/>      timeout             = optional(number, 5)<br/>      healthy_threshold   = optional(number, 3)<br/>      unhealthy_threshold = optional(number, 3)<br/>      matcher             = optional(string, "200")<br/>    }), {})<br/>    deregistration_delay = optional(number, 30)<br/>  }))</pre> | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the ALB, its security group, and its target groups are created in. | `string` | n/a | yes |
| <a name="input_web_acl_arn"></a> [web\_acl\_arn](#input\_web\_acl\_arn) | ARN of a REGIONAL-scope WAFv2 web ACL (for example from aws.modules.waf) to associate with the ALB. Optional: this module takes the ARN as a plain input and never calls aws.modules.waf itself, the same "every external dependency is an identifier the caller passes in" pattern as aws.modules.ksm and aws.modules.state. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the ALB. |
| <a name="output_alb_arn_suffix"></a> [alb\_arn\_suffix](#output\_alb\_arn\_suffix) | ARN suffix of the ALB, needed by CloudWatch metrics and by aws.modules.global-accelerator's health checks. |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the ALB. |
| <a name="output_alb_zone_id"></a> [alb\_zone\_id](#output\_alb\_zone\_id) | Route 53 hosted zone ID of the ALB, for an alias record through aws.modules.route53. |
| <a name="output_http_listener_arn"></a> [http\_listener\_arn](#output\_http\_listener\_arn) | ARN of the HTTP listener (redirect or http-only), or null when redirect\_http\_to\_https = false and create\_http\_only = false, in which case no port 80 listener exists. |
| <a name="output_https_listener_arn"></a> [https\_listener\_arn](#output\_https\_listener\_arn) | ARN of the HTTPS listener, or null when create\_http\_only = true and no HTTPS listener exists. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the ALB's security group. |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Plain ARN of each target group, keyed by the same keys as the target\_groups input. Drop this straight into aws.modules.ecs-service's load\_balancers[*].target\_group\_arn with no translation: this is the module's interface contract with ecs-service, proved in tests/target\_group\_arns.tftest.hcl. |
<!-- END_TF_DOCS -->
