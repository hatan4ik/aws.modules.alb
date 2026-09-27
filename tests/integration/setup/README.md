# Integration fixture

Disposable prerequisites for `tests/integration/smoke.tftest.hcl`: a VPC with
two public subnets, an internet gateway, and a shared public route table,
named with a random suffix so concurrent runs never collide. The smoke suite
uses `create_http_only = true`, so no ACM certificate is needed and nothing
here is more than a genuinely public pair of subnets for the ALB itself. Not
a deployable pattern: excluded from policy scanning (`.checkov.yml`,
`trivy.yaml`) and created and destroyed entirely by `terraform test`.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
