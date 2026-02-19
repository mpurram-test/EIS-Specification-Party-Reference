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
  spec_folder_path = abspath("${path.root}/${var.spec_folder}")
  api_files        = [for f in fileset(local.spec_folder_path, "*.y*ml") : f if strcontains(f, " v")]

  # 1. Create a flat list of all parsed APIs. This is unchanged and correct.
  parsed_apis = [
    for relpath in local.api_files : {
      name_part    = regex(var.filename_regex, basename(relpath))[0]
      version_part = regex(var.filename_regex, basename(relpath))[1]
      clean_path   = lower(join("-", [for p in split("-", replace(regex(var.filename_regex, basename(relpath))[0], " ", "-")) : p if p != ""]))
      version_str  = "${var.version_prefix}${regex(var.filename_regex, basename(relpath))[1]}"
      version_key  = "${lower(join("-", [for p in split("-", replace(regex(var.filename_regex, basename(relpath))[0], " ", "-")) : p if p != ""]))}-${var.version_prefix}${regex(var.filename_regex, basename(relpath))[1]}"
      original_file = relpath
    }
  ]

  # Get a list of the unique, clean family paths (e.g., ["...eis", "...fis"]).
  unique_family_paths = distinct([for api in local.parsed_apis : api.clean_path])

  # Loop over the UNIQUE paths to build the map, guaranteeing no duplicates.
  apis_grouped_by_family = {
    for family_path in local.unique_family_paths :
    family_path => {
      # Find the full display name from the first API that matches this family.
      display_name = [for api in local.parsed_apis : api.name_part if api.clean_path == family_path][0]
      
      # Now, build the versions map by filtering all APIs for the current family.
      versions = {
        for v in local.parsed_apis :
        v.version_key => {
          version_str   = v.version_str
          original_file = v.original_file
        } if v.clean_path == family_path # Filter condition
      }
    }
  }
  # --- END OF FIX ---
}

# -------------------------------------------
# DYNAMIC Version Sets (one per family)
# -------------------------------------------
resource "azurerm_api_management_api_version_set" "this" {
  for_each            = local.apis_grouped_by_family
  
  name                = "vs-${each.key}"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  display_name        = each.value.display_name
  versioning_scheme   = "Segment"
}

# -------------------------------------------
# Fail early guard
# -------------------------------------------
resource "null_resource" "ensure_specs_exist" {
  count = var.fail_if_no_specs ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(local.api_files) > 0
      error_message = "No versioned spec files found in folder: ${local.spec_folder_path}"
    }
  }
}

# -------------------------------------------
# Create one API per version
# -------------------------------------------
resource "azurerm_api_management_api" "apis" {
  for_each = merge([
    for clean_path, family_details in local.apis_grouped_by_family : {
      for version_key, version_details in family_details.versions :
      version_key => {
        clean_path    = clean_path
        display_name  = family_details.display_name
        version_str   = version_details.version_str
        original_file = version_details.original_file
      }
    }
  ]...)
  
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  name                = each.key
  display_name        = each.value.display_name
  path                = each.value.clean_path
  protocols           = ["https"]
  
  version_set_id      = azurerm_api_management_api_version_set.this[each.value.clean_path].id
  version             = each.value.version_str
  
  revision            = "1"

  import {
    content_format = "openapi"
    content_value  = file("${local.spec_folder_path}/${each.value.original_file}")
  }
}

# -----------------------
# Outputs
# -----------------------
output "api_count" {
  description = "Total API versions processed"
  value       = length(local.api_files)
}

output "deployed_version_sets" {
  description = "A summary of the Version Sets that were created."
  value       = [for vs in azurerm_api_management_api_version_set.this : { Name = vs.name, DisplayName = vs.display_name }]
}

output "deployed_api_details" {
  description = "A summary of the API versions that were deployed."
  value = {
    for api in azurerm_api_management_api.apis :
    api.name => {
      display_name     = api.display_name
      version          = api.version
      path_suffix      = api.path
      full_example_url = "https://{apim-host}/${api.path}/${api.version}"
    }
  }
}
