variable "name_prefix" {
  description = "Prefix for every disposable resource name; a random suffix is appended."
  type        = string
  nullable    = false
}

variable "cidr_block" {
  description = "CIDR block of the disposable VPC."
  type        = string
  default     = "10.91.0.0/16"
  nullable    = false
}

variable "tags" {
  description = "Additional tags merged onto every disposable resource."
  type        = map(string)
  default     = {}
  nullable    = false
}
