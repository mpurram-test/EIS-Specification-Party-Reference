terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }
}

provider "azurerm" {
  features {}
}

# -----------------------
# 1) Discover & Parse
# -----------------------
locals {
  # Find versioned specs (skip anything containing 'Definitions')
  api_files = [
    for f in fileset(var.spec_folder, "* v*.ya?ml") :
    f if !regexmatch(".*Definitions.*", f)
  ]

  # Build a map of parsed fields per file
  parsed = {
    for relpath in local.api_files :
    relpath => {
      base = basename(relpath)

      # Capture groups from filename using your regex:
      # groups[0] = base name, groups[1] = version number
      groups = regex(var.filename_regex, basename(relpath))

      name_group  = local.parsed_dummy[relpath].groups[0] # set via trick below
      version_num = local.parsed_dummy[relpath].groups[1]

      # Technical API name: spaces -> '-', then strip non [a-z0-9-], lowercase
      api_name = lower(
        regexreplace(
          replace(local.parsed_dummy[relpath].groups[0], " ", "-"),
          "[^a-z0-9-]",
          "-"
        )
      )

      # API display name you want to see in APIM, prefixed with "/"
      display_name_prefixed = "/${lower(
        regexreplace(
          replace(local.parsed_dummy[relpath].groups[0], " ", "-"),
          "[^a-z0-9-]",
          "-"
        )
      )}"

      # API URL suffix (path) for Segment routing:
      # Remove the literal token " - Party ", normalize, collapse dashes, trim
      path_suffix = lower(
        trim(
          regexreplace(
            regexreplace(
              replace(
                local.parsed_dummy[relpath].groups[0],
                " - Party ",
                " "
              ),
              " +",
              "-"
            ),
            "[^a-z0-9-]",
            "-"
          ),
          "-"
        )
      )

      # Human-friendly base (unused in resources; here for reference)
      display_name = regexreplace(basename(relpath), "\\.ya?ml$", "")

      # APIM version string, e.g., "v1"
      version = "${var.version_prefix}${local.parsed_dummy[relpath].groups[1]}"
    }
  }

  # Trick to reference groups above without re-running regex() repeatedly
  parsed_dummy = {
    for relpath in local.api_files :
    relpath => {
      groups = regex(var.filename_regex, basename(relpath))
    }
  }
}

# -------------------------------------------
# 2) Optional Version Set (Segment scheme)
# -------------------------------------------
resource "azurerm_api_management_api_version_set" "this" {
  count               = var.enable_version_set ? 1 : 0
  name                = "version-set-${var.api_management_name}"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = var.version_set_name
  versioning_scheme   = "Segment"
}

# -------------------------------------------
# 2a) Early failure if no specs (optional but recommended)
# -------------------------------------------
resource "null_resource" "ensure_specs_exist" {
  count = var.fail_if_no_specs ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(local.api_files) > 0
      error_message = "No bundled versioned specs found in spec_folder: ${var.spec_folder}"
    }
  }
}

# -------------------------------------------
# 3) One APIM API per spec
# -------------------------------------------
resource "azurerm_api_management_api" "apis" {
  for_each            = local.parsed

  name                = each.value.api_name
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  # Display name like: "/party-reference-data-directory---party-eis"
  display_name        = each.value.display_name_prefixed

  # With "Segment" versioning, APIM route is: /{path}/{version}
  # Path should be the cleaned suffix like: "party-reference-data-directory-eis"
  path                = each.value.path_suffix
  protocols           = ["https"]

  # Attach to version set if enabled
  # (Safe because the right-hand side is only evaluated when enable_version_set = true)
  version_set_id = var.enable_version_set ? azurerm_api_management_api_version_set.this[0].id : null

  version  = each.value.version
  revision = "1"

  import {
    content_format = "openapi+yaml"
    content_value  = file("${var.spec_folder}/${each.key}")
  }
}

# -----------------------
# 4) Helpful Outputs
# -----------------------
output "imported_api_names" {
  description = "APIs created/updated in APIM"
  value       = [for a in azurerm_api_management_api.apis : a.name]
}

output "api_count" {
  description = "Total APIs processed from spec_folder"
  value       = length(azurerm_api_management_api.apis)
}

output "version_set_id" {
  description = "Version set id (if enabled)"
  value       = var.enable_version_set ? azurerm_api_management_api_version_set.this[0].id : null
}