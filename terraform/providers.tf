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
  client_id       = "01cbbbbc-b507-438b-adcd-ba1910d72cec"
  tenant_id       = "72f988bf-86f1-41af-91ab-2d7cd011db47"
  subscription_id = "b2e1e2e2-2e2e-2e2e-2e2e-b2e1e2e2e2e2"
}