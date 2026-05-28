terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {}
variable "environment" {}
variable "service_name" {}
variable "location" { default = "westeurope" }
variable "vnet_address_prefix" { default = "10.0.0.0/25" }
variable "pe_frontend_subnet_prefix" { default = "10.0.0.0/27" }
variable "scalable_subnet_prefix" { default = "10.0.0.32/27" }

locals {
  spoke_name       = "${var.environment}-${var.service_name}"
  network_rg_name  = "${local.spoke_name}-network"
  tags = {
    Environment = var.environment
    Service     = var.service_name
    ManagedBy   = "Innofactor"
  }
}

resource "azurerm_resource_group" "network" {
  name     = local.network_rg_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_network_security_group" "pe_frontend" {
  name                = "${local.spoke_name}-network-PeFrontendSubnet-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

resource "azurerm_virtual_network" "spoke" {
  name                = "${local.spoke_name}-network-vnet"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = [var.vnet_address_prefix]
  tags                = local.tags
}

resource "azurerm_subnet" "pe_frontend" {
  name                 = "PeFrontendSubnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.pe_frontend_subnet_prefix]

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "pe_frontend" {
  subnet_id                 = azurerm_subnet.pe_frontend.id
  network_security_group_id = azurerm_network_security_group.pe_frontend.id
}

resource "azurerm_subnet" "scalable" {
  name                 = "ScalableSubnet"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [var.scalable_subnet_prefix]

  delegation {
    name = "Microsoft.App.environments"
    service_delegation {
      name = "Microsoft.App/environments"
    }
  }
}
