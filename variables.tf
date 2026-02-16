variable "resource_group_name" {
  description = "Resource group that contains the existing APIM instance"
  type        = string
}

variable "api_management_name" {
  description = "Existing Azure API Management service name"
  type        = string
}

# Jenkins writes bundled YAMLs here; Terraform reads only versioned entrypoints.
variable "openapi_glob" {
  description = "Glob for versioned bundled OpenAPI YAMLs"
  type        = string
  default     = "build/api-bundled/* v*.yaml"
}

variable "revision" {
  description = "APIM API revision (non‑breaking changes)"
  type        = string
  default     = "1"
}

variable "api_path_override" {
  description = "Optional override for API base path (keep version‑neutral; Version Set adds /vN)"
  type        = string
  default     = null
}

variable "service_url" {
  description = "Optional backend URL (ex: https://myapp.azurewebsites.net)"
  type        = string
  default     = null
}