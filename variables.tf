variable "resource_group_name" {
  description = "Azure Resource Group name where APIM lives."
  type        = string
}

variable "api_management_name" {
  description = "Azure API Management service name."
  type        = string
}

variable "spec_folder" {
  description = "Folder containing OpenAPI spec files (e.g., 'build/api-bundled')."
  type        = string
  default     = "build/api-bundled"
}

variable "filename_regex" {
  description = "Regex with group 1 for API name and group 2 for version number."
  type        = string
  # This default matches filenames like "My API v1.yaml"
  default = "(.*) v([0-9]+(?:\\.[0-9]+)*)"
}

variable "version_prefix" {
  description = "Prefix for APIM version string (e.g., 'v' -> v1)."
  type        = string
  default     = "v"
}

variable "fail_if_no_specs" {
  description = "Whether to fail the plan if no matching specs are found."
  type        = bool
  default     = true
}

variable "enable_version_set" {
  description = "Create and attach a Version Set. IMPORTANT: This should be true for versioning by URL segment."
  type        = bool
  default     = true
}
