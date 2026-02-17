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

  # Early safety guard (fails on plan if requested and no files are found)
  _assert_specs_present = (
    var.fail_if_no_specs && length(local.api_files) == 0
    ? tobool("No bundled versioned specs found in spec_folder: ${var.spec_folder}")
    : true
  )

  # Build a map: relpath -> parsed fields
  parsed = {
    for relpath in local.api_files :
    relpath => {
      base         = basename(relpath)

      # Extract from filename: group1=name, group2=version num
      name_raw     = regex(var.filename_regex, basename(relpath))[0] # full match
      name_group   = regex(var.filename_regex, basename(relpath))[1] # e.g., "Party Reference Data Directory - Party EIS"
      version_num  = regex(var.filename_regex, basename(relpath))[2] # e.g., "1"

      # Technical API name (keeps triple-dash effect from " - ")
      # Steps: spaces -> '-', replace any non [a-z0-9-] with '-', then lowercase
      api_name = lower(
        regexreplace(
          replace(regex(var.filename_regex, basename(relpath))[1], " ", "-"),
          "[^a-z0-9-]",
          "-"
        )
      )

      # API display name you want to see in APIM:
      # leading "/" + same normalization used for api_name
      display_name_prefixed = "/${lower(
        regexreplace(
          replace(regex(var.filename_regex, basename(relpath))[1], " ", "-"),
          "[^a-z0-9-]",
          "-"
        )
      )}"

      # API URL suffix (path) for Segment routing:
      # Remove the exact token " - Party ", normalize, collapse dashes, trim
      # Example: "Party Reference Data Directory - Party EIS" -> "party-reference-data-directory-eis"
      path_suffix = lower(
        trim(
          regexreplace(
            regexreplace(
              replace(
                # 1) remove the literal token
                regex(var.filename_regex, basename(relpath))[1],
                " - Party ",
                " "
              ),
              # 2) turn one or more spaces into single '-'
              " +",
              "-"
            ),
            # 3) replace any remaining non [a-z0-9-] with '-'
            "[^a-z0-9-]",
            "-"
          ),
          "-" # 4) trim leading/trailing dashes
        )
      )

      # Human-friendly base (unused in resources; here for reference)
      display_name = regexreplace(basename(relpath), "\\.ya?ml$", "")

      # APIM version string, e.g., "v1"
      version      = "${var.version_prefix}${regex(var.filename_regex, basename(relpath))[2]}"
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
  version_set_id      = var.enable_version_set && length(azurerm_api_management_api_version_set.this) > 0
                        ? azurerm_api_management_api_version_set.this[0].id
                        : null
  version             = each.value.version
  revision            = "1"

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
  value       = var.enable_version_set && length(azurerm_api_management_api_version_set.this) > 0
               ? azurerm_api_management_api_version_set.this[0].id
               : null
}