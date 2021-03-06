locals {
  resource_group_name       = "rg-zv-${var.environment}"
  container_registry_name   = "acrzv${var.environment}"
}

resource "azurerm_resource_group" "zv-rg" {
  name     = local.resource_group_name
  location = var.location

  tags = { environment = var.environment }
}

resource "azurerm_container_registry" "zv-acr" {
  name                     = local.container_registry_name
  resource_group_name      = azurerm_resource_group.zv-rg.name
  location                 = azurerm_resource_group.zv-rg.location
  sku                      = "Standard"
  admin_enabled            = true
}

data "azurerm_key_vault" "kv" {
  name                = "zvkv"
  resource_group_name = "zvstore"
}

data "azurerm_key_vault_secret" "kvAppRegSecret" {
  name      = "appRegSecret"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "kvSSHKey" {
  name      = "ssh-key-linux-profile"
  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "random_id" "log_analytics_workspace_name_suffix" {
    byte_length = 8
}

resource "azurerm_log_analytics_workspace" "test" {
    # The WorkSpace name has to be unique across the whole of azure, not just the current subscription/tenant.
    name                = "${var.log_analytics_workspace_name}-${random_id.log_analytics_workspace_name_suffix.dec}"
    location            = var.log_analytics_workspace_location
    resource_group_name = azurerm_resource_group.zv-rg.name
    sku                 = var.log_analytics_workspace_sku
}

resource "azurerm_log_analytics_solution" "test" {
    solution_name         = "ContainerInsights"
    location              = azurerm_log_analytics_workspace.test.location
    resource_group_name   = azurerm_resource_group.zv-rg.name
    workspace_resource_id = azurerm_log_analytics_workspace.test.id
    workspace_name        = azurerm_log_analytics_workspace.test.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}

resource "azurerm_kubernetes_cluster" "zv-k8s" {
    name                = var.cluster_name
    location            = azurerm_resource_group.zv-rg.location
    resource_group_name = azurerm_resource_group.zv-rg.name
    dns_prefix          = var.dns_prefix

    linux_profile {
        admin_username = "ubuntu"

        ssh_key {
            key_data = data.azurerm_key_vault_secret.kvSSHKey.value
        }
    }

    default_node_pool {
        name            = "agentpool"
        node_count      = var.agent_count
        vm_size         = "Standard_D2_v2"
    }

    service_principal {
        client_id     = var.client_id
        client_secret = data.azurerm_key_vault_secret.kvAppRegSecret.value
    }

    addon_profile {
        oms_agent {
        enabled                    = true
        log_analytics_workspace_id = azurerm_log_analytics_workspace.test.id
        }
        http_application_routing {
        enabled = true
        }        
    }

    network_profile {
        load_balancer_sku = "Standard"
        network_plugin = "kubenet"
    }

    tags = {
        Environment = "Development"
    }
}


output "admin_password" {
  value       = azurerm_container_registry.zv-acr.admin_password
  description = "The object ID of the user"
}