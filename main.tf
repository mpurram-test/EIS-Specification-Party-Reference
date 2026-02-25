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

# 1) Discover & Parse

locals {
  spec_folder_path = abspath("${path.root}/${var.spec_folder}")

  api_files = [
    for f in fileset(local.spec_folder_path, "*.y*ml") :
    f
    if can(regex(var.filename_regex, basename(f)))
  ]
  parsed_apis = [
    for relpath in local.api_files : {
      name_part       = regex(var.filename_regex, basename(relpath))[0]
      version_part    = regex(var.filename_regex, basename(relpath))[1]
      name_part_clean = trim(regexreplace(name_part, " - .*? Entity", ""))
      clean_path_fallback = lower(
        replace(
          replace(
            replace(name_part_clean, " ", "-"),
            "--", "-"
          ),
          "---", "-"
        )
      )

      server_url = trim(tostring(try(yamldecode(file("${local.spec_folder_path}/${relpath}")).servers[0].url, "")))

      server_path_full = try(regex("^https?://[^/]+(/[^?#]*)", server_url)[0], "")

      server_first_segment = length(server_path_full) > 1 ? split("/", trim(server_path_full, "/"))[0] : ""

      api_path = length(trim(server_first_segment)) > 0 ? server_first_segment : clean_path_fallback

      description = trim(tostring(try(yamldecode(file("${local.spec_folder_path}/${relpath}")).info.description, "")))

      version_str = "${var.version_prefix}${version_part}"
      version_key = "${api_path}-${version_str}"

      original_file = relpath
    }
  ]

  unique_family_paths = distinct([for api in local.parsed_apis : api.api_path])
  apis_grouped_by_family = {
    for family_path in local.unique_family_paths :
    family_path => {
      display_name = [for api in local.parsed_apis : api.name_part_clean if api.api_path == family_path][0]

      versions = {
        for v in local.parsed_apis :
        v.version_key => {
          version_str   = v.version_str
          original_file = v.original_file
          description   = v.description
          api_path      = v.api_path
        } if v.api_path == family_path
      }
    }
  }
}


# 2) DYNAMIC Version Sets

resource "azurerm_api_management_api_version_set" "this" {
  for_each            = local.apis_grouped_by_family
  name                = "vs-${each.key}"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  display_name      = each.value.display_name
  versioning_scheme = "Segment"
}


# 2a) Fail early guard

resource "null_resource" "ensure_specs_exist" {
  count = var.fail_if_no_specs ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(local.api_files) > 0
      error_message = "No versioned spec files found in folder: ${local.spec_folder_path}"
    }
  }
}

# 3) Create one API per version

resource "azurerm_api_management_api" "apis" {
  for_each = merge([
    for family_path, family_details in local.apis_grouped_by_family : {
      for version_key, version_details in family_details.versions :
      version_key => {
        api_path      = version_details.api_path
        display_name  = family_details.display_name
        version_str   = version_details.version_str
        original_file = version_details.original_file
        description   = version_details.description
      }
    }
  ]...)

  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  name           = each.key
  display_name   = each.value.display_name
  description    = length(each.value.description) > 0 ? each.value.description : null
  path           = each.value.api_path
  protocols      = ["https"]
  service_url    = var.backend_service_url
  version_set_id = azurerm_api_management_api_version_set.this[each.value.api_path].id
  version        = each.value.version_str
  revision       = "1"

  import {
    content_format = "openapi"
    content_value  = file("${local.spec_folder_path}/${each.value.original_file}")
  }
}

# 3b) Products 

resource "azurerm_api_management_product" "quavo" {
  product_id          = var.product_quavo_id
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  display_name          = var.product_quavo_display
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product" "seacoast_internal" {
  product_id          = var.product_seacoast_id
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  display_name          = var.product_seacoast_display
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "quavo__eis_v1" {
  for_each = {
    for k, v in azurerm_api_management_api.apis : k => v
    if can(regex(".*-eis-v1$", k))
  }

  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  product_id          = azurerm_api_management_product.quavo.product_id
  api_name            = each.value.name
}

resource "azurerm_api_management_product_api" "seacoast_internal__eis_v1" {
  for_each = {
    for k, v in azurerm_api_management_api.apis : k => v
    if can(regex(".*-eis-v1$", k))
  }

  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  product_id          = azurerm_api_management_product.seacoast_internal.product_id
  api_name            = each.value.name
}

resource "azurerm_api_management_product_api" "seacoast_internal__fis_v1" {
  for_each = {
    for k, v in azurerm_api_management_api.apis : k => v
    if can(regex(".*-fis-v1$", k))
  }

  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  product_id          = azurerm_api_management_product.seacoast_internal.product_id
  api_name            = each.value.name
}

resource "azurerm_api_management_subscription" "quavo_sub" {
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = var.subscription_quavo_display
  state               = "active"
  product_id          = azurerm_api_management_product.quavo.product_id
}

resource "azurerm_api_management_subscription" "seacoast_internal_sub" {
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name
  display_name        = var.subscription_seacoast_display
  state               = "active"
  product_id          = azurerm_api_management_product.seacoast_internal.product_id
}

# -----------------------
# 4) Outputs
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
