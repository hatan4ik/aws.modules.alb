## Summary

<!-- What changes and why. Link the issue this closes, if any. -->

## Type of change

- [ ] fix: bug fix, non-breaking
- [ ] feat: new input, output, or behaviour, non-breaking
- [ ] breaking: existing callers must change configuration or state
- [ ] docs: documentation only
- [ ] chore: tooling, CI, or dependencies

## Checklist

- [ ] Tests added or updated, and `terraform test` passes in every touched directory
- [ ] `make check` passes locally
- [ ] Docs regenerated with terraform-docs (`make docs`) in every touched directory
- [ ] `CHANGELOG.md` `Unreleased` section updated
- [ ] No data sources added beyond the one documented exception (`docs/DESIGN.md`)
- [ ] If `target_groups` or `target_group_arns` changed, `tests/target_group_arns.tftest.hcl` still proves the `ecs-service` interface contract
- [ ] Breaking changes documented in `docs/UPGRADE-<version>.md`
