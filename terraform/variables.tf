variable "resource_group_name" { type = string }
variable "api_management_name" { type = string }
variable "fail_if_no_specs" {
  type    = bool
  default = true
}

variable "attach_api_policy" {
  type    = bool
  default = true
}
variable "spec_folder" {
  description = "Folder containing bundled OpenAPI spec files."
  type        = string
  default     = "../build/api-bundled"
}
