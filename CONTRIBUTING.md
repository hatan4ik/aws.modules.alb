# Contributing

Thank you for improving `aws.modules.alb`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## Integration suite

`tests/integration/` holds a credential-driven suite that applies the module for real and destroys everything afterwards. It is never part of `make check` or the quality pipeline. Run it against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke   # a few minutes; a disposable VPC, one HTTP-only ALB with one target group, destroyed at the end
```

Add a suite when a feature's correctness depends on the AWS API rather than on rendering (for example a new listener or health check shape). Keep every value derived from the environment or from disposable fixtures the suite creates, and never reference a real VPC, certificate, or account. A suite that needs fixtures keeps them in `tests/integration/setup`, which the policy scans exclude.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root and every example directory. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root. No credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init` before the docs drift check, so a lock file missing the Linux hash gets rewritten and fails that check. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason on the resource it concerns, or a documented entry in `.checkov.yml` when it applies across the whole module; see the comments there. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl`, one file per concern: `defaults`, `validation` (every variable validation and precondition), `listeners`, `listener_rules`, `waf`, `access_logs`, `checks`, and `target_group_arns` (the interface contract with `aws.modules.ecs-service`). Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Prefer `command = plan` for anything that does not need a concrete ARN or ID: it is instant and needs no `mock_resource` defaults. Reach for `command = apply` only when an assertion genuinely needs a resolved value (an ARN equality check, a `target_group_arns` output value) — under `command = plan`, a not-yet-created resource's computed attributes are "known after apply" with any provider, mock or real, and a condition that depends on one fails with "Unknown condition value." Pin the resolved value with a `mock_resource "<type>" { defaults = { <attr> = "..." } }` block inside `mock_provider "aws" { ... }` so the mocked apply is deterministic rather than random filler.
- `run` blocks in one `.tftest.hcl` file share state: a `command = apply` run's created resources persist for later runs in the same file. Never mix `plan` and `apply` runs in one file; `tests/listeners.tftest.hcl`, `tests/listener_rules.tftest.hcl`, and `tests/target_group_arns.tftest.hcl` are apply-only for this reason, and the rest stay plan-only.
- Validations and preconditions are tested with `expect_failures`. Point it at the object that carries the check: `[var.target_groups]` for a variable validation, `[aws_lb.this]` for a precondition on the ALB, `[aws_lb_listener_rule.this]` for a precondition inside a `for_each` resource, `[check.public_without_waf]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- The default `security_group_ingress_cidrs` (`["0.0.0.0/0"]`) trips the advisory `public_without_waf` check on every plan unless `web_acl_arn` is set or the CIDR is overridden. Any test file not specifically exercising that check sets a private CIDR (for example `10.0.0.0/16`) in its baseline `variables` block so unrelated runs are not surprised by it.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- A block type that is a set (`condition` on `aws_lb_listener_rule`, for example) cannot be indexed with `[0]`; use `one(...)` to extract its single element, or a `for` expression with an `if` clause to filter it.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

The module has no submodules; concerns are split by file, and each file has one reason to change.

| Concern | Lives in |
| --- | --- |
| A new ALB-level argument (idle timeout, deletion protection, access logs) | `variables.tf` with a description, type, and validation; `alb.tf` to render it. |
| Security group rules | `security_group.tf`, driven by `locals.active_listener_ports` in `locals.tf`. |
| A target group argument | `variables.tf`'s `target_groups` object type and its validation; `target_groups.tf` to render it; a test in `tests/validation.tftest.hcl` and, if it changes the interface with `ecs-service`, `tests/target_group_arns.tftest.hcl`. |
| Listener shape (HTTPS, HTTP-only, redirect, SNI) | `listeners.tf`, `locals.tf`'s listener-existence flags, pinned in `tests/listeners.tftest.hcl`. |
| Path/host-based routing | `listener_rules.tf`, pinned in `tests/listener_rules.tftest.hcl`. |
| Cross-input rules | Preconditions on `aws_lb.this` (`alb.tf`), the listener resources (`listeners.tf`), or `aws_lb_listener_rule.this` (`listener_rules.tf`); or `checks.tf` when the situation is valid but usually unintended. |
| Outputs | `outputs.tf`; every output has a description, and `target_group_arns`'s key-shape guarantee is asserted directly in a test, never just implied. |

Rules that apply everywhere: no data sources beyond the one documented exception in `docs/DESIGN.md` (the VPC CIDR for security group egress), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, and an input that applies to one mode (HTTPS vs. HTTP-only) is rejected in the other rather than ignored.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or concern the change touches.

```text
feat(listeners): support authenticate-oidc listener actions
fix(security_group): scope ingress to active listener ports only
docs: explain the VPC CIDR data source deviation
test(listener_rules): cover duplicate priorities across two rules
feat!: rename target_group_arns to target_group_arn_by_key
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in an upgrade guide (`docs/UPGRADE-<major>.md`, added the first time this module ships a breaking change).

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and a new or updated `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No new data sources beyond the one documented exception, no hard-coded account, region, or partition, no new defaults that weaken security.
- [ ] Any change to `target_groups` or `target_group_arns` re-runs `tests/target_group_arns.tftest.hcl` and, if the shape changes, updates the interface contract description in `docs/DESIGN.md`.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.alb vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies the signed tag, formatting, validation, tests, and generated docs, then publishes the GitHub release. Never dispatch it from `main`: the workflow checks that the tag points at the revision it checked out, and a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.alb.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
