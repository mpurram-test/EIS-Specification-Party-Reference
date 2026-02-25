variable "resource_group_name" {
  description = "Azure Resource Group name where APIM lives."
  type        = string
}

variable "api_management_name" {
  description = "Azure API Management service name."
  type        = string
}

variable "spec_folder" {
  description = "Folder containing bundled OpenAPI spec files."
  type        = string
  default     = "build/api-bundled"
}

variable "filename_regex" {
  description = "Regex with group 1 for API name and group 2 for version number; matches '<Name> v<Version>.yaml'."
  type        = string
  default     = "(.*) v([0-9]+(?:\\.[0-9]+)*)"
}

variable "version_prefix" {
  description = "Prefix for APIM version string (e.g., 'v' -> v1)."
  type        = string
  default     = "v"
}

variable "fail_if_no_specs" {
  description = "Whether to fail the plan/apply if no matching specs are found."
  type        = bool
  default     = true
}

variable "backend_service_url" {
  description = "Default backend origin (scheme+host) APIM should forward to. Ex: https://backend.example.com"
  type        = string
}

variable "product_quavo_id" {
  description = "Product identifier for Quavo."
  type        = string
  default     = "quavo"
}

variable "product_quavo_display" {
  description = "Display name for the Quavo product."
  type        = string
  default     = "Quavo"
}

variable "product_seacoast_id" {
  description = "Product identifier for Seacoast Internal."
  type        = string
  default     = "seacoast-internal"
}

variable "product_seacoast_display" {
  description = "Display name for the Seacoast Internal product."
  type        = string
  default     = "Seacoast Internal"
}

variable "subscription_quavo_name" {
  description = "Subscription resource name for Quavo."
  type        = string
  default     = "quavo-subscription"
}

variable "subscription_quavo_display" {
  description = "Display name for Quavo product subscription."
  type        = string
  default     = "Quavo Product Subscription"
}

variable "subscription_seacoast_name" {
  description = "Subscription resource name for Seacoast Internal."
  type        = string
  default     = "seacoast-internal-subscription"
}

variable "subscription_seacoast_display" {
  description = "Display name for Seacoast Internal product subscription."
  type        = string
  default     = "Seacoast Internal Product Subscription"
}
