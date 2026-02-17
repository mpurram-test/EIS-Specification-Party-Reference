############################################
# variables.tf
############################################

variable "resource_group_name" {
  description = "Azure Resource Group name where APIM lives"
  type        = string
}

variable "api_management_name" {
  description = "Azure API Management service name"
  type        = string
}

variable "spec_folder" {
  description = "Folder containing OpenAPI spec files"
  type        = string
  default     = "specs"
}

variable "filename_regex" {
  description = <<EOT
Regex with:
  - group 1: API base name (before ' v<digits>.ya?ml')
  - group 2: version number (digits)
Matches filenames like: "Payments v1.yaml" or "Orders v2.yml"
EOT
  type    = string
  default = "^(.*) v([0-9]+)\\.ya?ml$"
}

variable "version_prefix" {
  description = "Prefix for APIM version string (e.g., 'v' -> v1)"
  type        = string
  default     = "v"
}

variable "fail_if_no_specs" {
  description = "Whether to fail the plan if no matching specs are found"
  type        = bool
  default     = true
}

variable "enable_version_set" {
  description = "Create and attach a Version Set using Segment scheme"
  type        = bool
  default     = true
}

variable "version_set_name" {
  description = "Display name for the APIM Version Set"
  type        = string
  default     = "APIs Version Set"
}