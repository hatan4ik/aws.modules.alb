# ---------------------------------------------------------------------------
# Identity and network
# ---------------------------------------------------------------------------

variable "name" {
  description = "Name of the ALB. AWS caps load balancer names at 32 characters, alphanumeric and hyphens, must not start or end with a hyphen, and must not start with \"internal-\" (an AWS-reserved prefix regardless of the internal input). Also used to derive the security group name and every target group name (name-<key>), so keep it short enough to leave room for your longest target_groups key."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,32}$", var.name)) && !startswith(var.name, "-") && !endswith(var.name, "-") && !startswith(var.name, "internal-")
    error_message = "name must be 1-32 characters of letters, digits, or hyphens, must not start or end with a hyphen, and must not start with the AWS-reserved prefix \"internal-\"."
  }
}

variable "internal" {
  description = "false (default) creates an internet-facing ALB in public_subnet_ids, which is this module's whole purpose per ADR-0004. Set true only for a documented internal-only need; public_subnet_ids still names the subnets the ALB's network interfaces are created in."
  type        = bool
  default     = false
  nullable    = false
}

variable "vpc_id" {
  description = "VPC the ALB, its security group, and its target groups are created in."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID such as vpc-0123456789abcdef0."
  }
}

variable "public_subnet_ids" {
  description = "Subnets the ALB's network interfaces are created in, at least two in different Availability Zones. Named for this module's normal internet-facing case (ADR-0004); still the subnet set to use when internal = true."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "public_subnet_ids must contain at least two subnets in different Availability Zones."
  }

  validation {
    condition     = alltrue([for id in var.public_subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", id))])
    error_message = "Every public_subnet_ids entry must be a subnet ID such as subnet-0123456789abcdef0."
  }
}

# ---------------------------------------------------------------------------
# TLS and listeners
# ---------------------------------------------------------------------------

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener, for example from the already-released aws.modules.acm. Required unless create_http_only = true, and must be left unset when it is (a precondition on the ALB enforces this exactly-one-path rule)."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn == null ? true : can(regex("^arn:[a-z0-9-]+:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN (arn:<partition>:acm:<region>:<account>:certificate/<uuid>)."
  }
}

variable "additional_certificate_arns" {
  description = "Further ACM certificate ARNs attached to the HTTPS listener for SNI. Must be empty when create_http_only = true, since there is then no HTTPS listener to attach them to."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.additional_certificate_arns : can(regex("^arn:[a-z0-9-]+:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$", arn))])
    error_message = "Every additional_certificate_arns entry must be an ACM certificate ARN (arn:<partition>:acm:<region>:<account>:certificate/<uuid>)."
  }
}

variable "create_http_only" {
  description = "false (default) serves HTTPS from certificate_arn, per ADR-0004's \"HTTPS at the edge\" decision. true skips the HTTPS listener entirely and serves plain HTTP only: a narrow escape hatch for a non-production ALB or one that sits behind something that already terminates TLS (for example a CloudFront or Global Accelerator hop that re-encrypts elsewhere) — never a default anyone should reach for. Mutually exclusive-required with certificate_arn: exactly one of the two paths is valid, enforced by a precondition on the ALB."
  type        = bool
  default     = false
  nullable    = false
}

variable "redirect_http_to_https" {
  description = "true (default) creates an HTTP listener on port 80 whose only job is a 301 redirect to the HTTPS listener; false creates no port 80 listener at all, so the security group never opens it. Not applicable when create_http_only = true (there is no HTTPS listener to redirect to); a precondition rejects setting it to anything but its default true in that mode instead of silently ignoring the override."
  type        = bool
  default     = true
  nullable    = false
}

variable "web_acl_arn" {
  description = "ARN of a REGIONAL-scope WAFv2 web ACL (for example from aws.modules.waf) to associate with the ALB. Optional: this module takes the ARN as a plain input and never calls aws.modules.waf itself, the same \"every external dependency is an identifier the caller passes in\" pattern as aws.modules.ksm and aws.modules.state."
  type        = string
  default     = null

  validation {
    condition     = var.web_acl_arn == null ? true : can(regex("^arn:[a-z0-9-]+:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/[a-zA-Z0-9-]+/[0-9a-f-]{36}$", var.web_acl_arn))
    error_message = "web_acl_arn must be a REGIONAL-scope WAFv2 web ACL ARN (arn:<partition>:wafv2:<region>:<account>:regional/webacl/<name>/<uuid>)."
  }
}

# ---------------------------------------------------------------------------
# ALB behaviour
# ---------------------------------------------------------------------------

variable "deletion_protection" {
  description = "true (default) blocks the ALB from being deleted until it is turned off. A check block warns, advisory only, when this is false."
  type        = bool
  default     = true
  nullable    = false
}

variable "idle_timeout" {
  description = "Seconds the ALB keeps an idle connection open, 1-4000."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout must be between 1 and 4000 seconds."
  }
}

variable "drop_invalid_header_fields" {
  description = "true (default) drops HTTP requests with invalid header fields, an AWS security best practice. This module is secure by default."
  type        = bool
  default     = true
  nullable    = false
}

variable "access_logs" {
  description = "Access log destination the caller already created and owns (for example through aws.modules.s3), and has already granted the regional ELB log-delivery service account permission to write to via that bucket's policy. This module only points the ALB at bucket_name (and optional prefix); it does not create the bucket or write its policy. null (default) leaves access logging off."
  type = object({
    bucket_name = string
    prefix      = optional(string)
  })
  default = null

  validation {
    condition     = var.access_logs == null ? true : length(var.access_logs.bucket_name) > 0
    error_message = "access_logs.bucket_name must not be empty when access_logs is set."
  }
}

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------

variable "security_group_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB's active listener ports (443 when HTTPS exists, 80 when an HTTP listener exists). Defaults to [\"0.0.0.0/0\"] since a public ALB is the point (ADR-0004), but must be set explicitly and non-empty: this module never silently defaults to an empty set that would make the ALB unreachable."
  type        = set(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.security_group_ingress_cidrs) > 0
    error_message = "security_group_ingress_cidrs must not be empty; an ALB with no ingress CIDR is unreachable. Keep the default [\"0.0.0.0/0\"] or set the CIDRs explicitly."
  }

  validation {
    condition     = alltrue([for cidr in var.security_group_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every security_group_ingress_cidrs entry must be a valid IPv4 CIDR, such as 10.0.0.0/8 or 0.0.0.0/0."
  }
}

# ---------------------------------------------------------------------------
# Target groups and routing
# ---------------------------------------------------------------------------

variable "target_groups" {
  description = "Target groups keyed by a short logical name, for example \"app\" or \"api\". These keys are also the keys of the target_group_arns output, so a caller folds that output straight into aws.modules.ecs-service's load_balancers map. target_type defaults to \"ip\", correct for Fargate awsvpc mode. At least one entry is required: an ALB with no target groups is meaningless."
  type = map(object({
    port        = number
    protocol    = optional(string, "HTTP")
    target_type = optional(string, "ip")
    health_check = optional(object({
      path                = optional(string, "/")
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
      matcher             = optional(string, "200")
    }), {})
    deregistration_delay = optional(number, 30)
  }))
  nullable = false

  validation {
    condition     = length(var.target_groups) > 0
    error_message = "target_groups must declare at least one entry; an ALB with no target groups is meaningless."
  }

  validation {
    condition     = alltrue([for key in keys(var.target_groups) : can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", key))])
    error_message = "Every target_groups key must be 1-32 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : tg.port >= 1 && tg.port <= 65535])
    error_message = "Every target_groups port must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : contains(["HTTP", "HTTPS"], tg.protocol)])
    error_message = "Every target_groups protocol must be HTTP or HTTPS."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : contains(["ip", "instance", "alb"], tg.target_type)])
    error_message = "Every target_groups target_type must be ip, instance, or alb. Use ip for Fargate awsvpc mode."
  }

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : tg.deregistration_delay >= 0 && tg.deregistration_delay <= 3600])
    error_message = "Every target_groups deregistration_delay must be between 0 and 3600 seconds."
  }

  validation {
    condition = alltrue([for tg in values(var.target_groups) : (
      tg.health_check.interval > tg.health_check.timeout &&
      tg.health_check.healthy_threshold >= 2 && tg.health_check.healthy_threshold <= 10 &&
      tg.health_check.unhealthy_threshold >= 2 && tg.health_check.unhealthy_threshold <= 10 &&
      can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", tg.health_check.matcher))
    )])
    error_message = "Every target_groups health_check must have interval greater than timeout, healthy_threshold and unhealthy_threshold between 2 and 10, and a matcher such as \"200\", \"200-299\", or \"200,201,202\"."
  }
}

variable "default_target_group_key" {
  description = "target_groups key the HTTPS (or HTTP-only) listener's default action forwards to. Must reference a real target_groups key; enforced by a precondition on the listener, since a variable validation cannot see another variable's value under Terraform 1.7."
  type        = string
  nullable    = false
}

variable "listener_rules" {
  description = "Path- or host-based routing rules beyond the default action, keyed by a short rule name. Each rule's target_group_key must reference a target_groups key (enforced by a precondition, not a variable validation, for the same cross-variable reason as default_target_group_key) and each rule needs at least one of conditions.path_patterns or conditions.host_headers. Rules attach to whichever listener actually serves traffic: HTTPS when it exists, otherwise the HTTP-only listener. Empty by default; the listener's default action alone then handles every request."
  type = map(object({
    priority         = number
    target_group_key = string
    conditions = object({
      path_patterns = optional(set(string))
      host_headers  = optional(set(string))
    })
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for rule in values(var.listener_rules) : rule.priority >= 1 && rule.priority <= 50000])
    error_message = "Every listener_rules priority must be between 1 and 50000."
  }

  validation {
    condition     = length(distinct([for rule in values(var.listener_rules) : rule.priority])) == length(var.listener_rules)
    error_message = "Every listener_rules priority must be unique."
  }

  validation {
    condition     = alltrue([for rule in values(var.listener_rules) : rule.conditions.path_patterns != null || rule.conditions.host_headers != null])
    error_message = "Every listener_rules entry must set at least one of conditions.path_patterns or conditions.host_headers."
  }

  validation {
    condition     = alltrue([for key in keys(var.listener_rules) : can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", key))])
    error_message = "Every listener_rules key must be 1-32 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "tags" {
  description = "Tags applied to every resource the module creates. The module adds a Name tag and never overrides caller tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
