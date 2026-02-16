terraform {
  required_version = ">= 1.4.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.55.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# --- Discover bundled, versioned OpenAPI YAMLs and compute values purely from filename ---
locals {
  # e.g., build/api-bundled/Party Reference Data Directory - Party EIS v1.yaml
  versioned_specs = fileset(path.module, var.openapi_glob)

  # Parse filename -> base name (display), version (vN), slugs, resource name, path
  apis = {
    for rel_path in local.versioned_specs : rel_path => {
      rel_path   = rel_path
      filename   = basename(rel_path)

      # Base display name = filename without trailing " v<digit>.yaml"
      base_name  = trim(regexreplace(basename(rel_path), "\\s+v\\d+\\.ya?ml$", ""), " ")

      # Version = capture "v<digit>" from end of filename
      version_id = lower(regexreplace(basename(rel_path), ".*\\s(v\\d+)\\.ya?ml$", "$1"))

      base_slug  = lower(regexreplace(base_name, "[^a-zA-Z0-9]+", "-"))
      api_path   = coalesce(var.api_path_override, base_slug)
      api_name   = "${base_slug}-${version_id}" # unique per version (resource name)
    }
  }

  # One Version Set per logical API (keyed by base_slug)
  version_sets = {
    for _, a in local.apis : a.base_slug => a.base_name...
  }
}

# --- Version Set per base API (Path/Segment versioning) ---
# APIM Path/Segment puts /v1/, /v2/ in the URL. [1](https://github.com/hashicorp/terraform-provider-azurerm/issues/8306)
resource "azurerm_api_management_api_version_set" "this" {
  for_each = local.version_sets

  name                = "${each.key}-versions"
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  display_name      = each.value[0]       # human-friendly base name
  versioning_scheme = "Segment"           # /v1/... /v2/...
}

# --- One APIM API per bundled version ---
# Import OpenAPI YAML using Terraform APIM API "import" (OpenAPI YAML supported). [2](https://stackoverflow.com/questions/61122830/using-terraform-yamldecode-to-access-multi-level-element)
resource "azurerm_api_management_api" "this" {
  for_each = local.apis

  name                = each.value.api_name
  resource_group_name = var.resource_group_name
  api_management_name = var.api_management_name

  revision     = var.revision
  display_name = each.value.base_name
  path         = each.value.api_path
  protocols    = ["https"]

  # Attach to Version Set with filename-derived version
  version        = each.value.version_id
  version_set_id = azurerm_api_management_api_version_set.this[each.value.base_slug].id

  import {
    content_format = "openapi"                      # YAML
    content_value  = file(each.value.rel_path)      # the bundled file content
  }

  # Optional backend URL for APIM to call
  # service_url = var.service_url
}

output "deployed_apis" {
  description = "Summary of deployed APIs"
  value = {
    for k, r in azurerm_api_management_api.this :
    k => {
      name         = r.name
      display_name = r.display_name
      version      = r.version
      path         = r.path
    }
  }
}