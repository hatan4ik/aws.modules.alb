# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan, and the impact you see. Redact account IDs, ARNs, and any real CIDR ranges.

## What counts

- A module default that weakens security: deletion protection off, HTTPS skipped without `create_http_only` explicitly set, `drop_invalid_header_fields` off, an unrestricted security group egress rule (this module never opens egress beyond the VPC's own CIDR).
- A validation bypass: an input the module claims to reject at plan time (a malformed ARN, a `target_groups`/`listener_rules` cross-reference, the `create_http_only`/`certificate_arn` exactly-one-path rule) that instead reaches the provider.
- The `target_group_arns` output producing a key set that does not exactly match `target_groups`, or a value that is not the plain ARN a caller can pass straight into `aws.modules.ecs-service`'s `load_balancers[*].target_group_arn`. This output's shape is the module's whole interface contract; any drift from it is a security- and correctness-relevant regression, not a cosmetic one.
- A listener rule attaching to the wrong listener, or a rule condition or priority not matching its declared input.
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example choosing `create_http_only = true` for a genuinely internal ALB, or a `security_group_ingress_cidrs` broader than you intended) or in AWS services themselves are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release of every supported line with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default: HTTPS at the edge unless `create_http_only` is explicitly set, `deletion_protection` and `drop_invalid_header_fields` both on, a security group with no inline rules (so AWS's own default allow-all egress is revoked at creation) and egress scoped to the VPC's own CIDR, ingress scoped to exactly the listener ports that exist, an explicit (never silently empty) `security_group_ingress_cidrs`, and advisory checks for disabled deletion protection and a public ALB with no WAF. Every claim is enforced by a validation, a precondition, or a `check` block with a `terraform test` case behind it. The full description is in [docs/DESIGN.md](docs/DESIGN.md).
