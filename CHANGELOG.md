# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

## [1.0.0] - 2026-09-27

Brand new module: no v0.x baseline, no live consumer, no upgrade guide. One module call provisions one regional Application Load Balancer per [ADR-0004](/docs/adr/0004-edge-ingress-and-egress.md): the ALB, its security group, its target groups, its HTTPS and/or HTTP listener, and any path/host-based listener rules.

### Added

- `aws_lb.this`: one Application Load Balancer, internet-facing by default (`internal = false`) with `deletion_protection` and `drop_invalid_header_fields` both true by default.
- `aws_security_group.this` with no inline rules: `aws_vpc_security_group_ingress_rule` per (active listener port, `security_group_ingress_cidrs` entry) pair, and `aws_vpc_security_group_egress_rule` scoped to the VPC's own CIDR, never left unrestricted.
- `aws_lb_target_group.this`, one per `target_groups` entry, `target_type` defaulting to `ip` for Fargate awsvpc mode, with a configurable health check and deregistration delay.
- `target_group_arns` output: a `map(string)` with exactly the same keys as `target_groups`, each value the plain target group ARN — designed to fold directly into the already-released `aws.modules.ecs-service` v1.0.0's `load_balancers` input with no translation. This is the module's whole reason for existing; see [docs/DESIGN.md](docs/DESIGN.md).
- HTTPS listener (`certificate_arn`, `additional_certificate_arns` via `aws_lb_listener_certificate` for SNI) and a redirecting or forwarding HTTP listener, chosen by `create_http_only` and `redirect_http_to_https`.
- `create_http_only`: a narrow escape hatch that skips the HTTPS listener entirely and serves plain HTTP, for a non-production ALB or one behind something that already terminates TLS. Mutually exclusive-required with `certificate_arn`.
- `listener_rules`: path- and host-based routing beyond the default action, attached to whichever listener actually serves traffic.
- `web_acl_arn`: optional association of a caller-supplied REGIONAL-scope WAFv2 web ACL through `aws_wafv2_web_acl_association`. This module never creates or owns the web ACL itself, the same external-dependency pattern as `aws.modules.ksm` and `aws.modules.state`.
- `access_logs`: points the ALB at a bucket the caller already created and granted access to (for example through `aws.modules.s3`); the module does not create the bucket or its policy.
- Plan-time validation of every input (name length and character set, VPC and subnet ID shape, ARN shapes, CIDR validity, target group and listener rule shapes) and preconditions for the cross-input rules a Terraform 1.7 variable validation cannot see (`default_target_group_key` and every `listener_rules[*].target_group_key` referencing a real `target_groups` key, the `create_http_only`/`certificate_arn` exactly-one-path rule, `additional_certificate_arns` and `redirect_http_to_https` rejected in HTTP-only mode, unique listener rule priorities, target group name length).
- Advisory `check` blocks `deletion_protection_disabled` and `public_without_waf`.
- Mock-provider contract tests in `tests/`: defaults, every validation and precondition, the HTTPS/HTTP-only/redirect listener matrix, listener rules, WAF association, access logs, both advisory checks, and `tests/target_group_arns.tftest.hcl`, which proves the `target_group_arns` → `ecs-service` `load_balancers` interface contract directly.
- Examples `minimal`, `path-based-routing`, `with-waf`, and `internal-http-only`.
- Credential-driven integration suite `smoke` in `tests/integration/` against a disposable VPC fixture (HTTP-only, avoiding the need for a real ACM certificate), a `make integration-smoke` target, a dispatch-only `integration` workflow, and the IAM trust and permissions documents the role needs.
- `docs/DESIGN.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, the `Makefile` quality gate, pre-commit, tflint, and terraform-docs configuration, Dependabot, issue and pull request templates, and the `module-release` workflow.

[Unreleased]: https://github.com/hatan4ik/aws.modules.alb/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.alb/releases/tag/v1.0.0
