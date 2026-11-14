locals {
  tags = {
    project     = "azure-cloud-mini-soc"
    environment = "lab"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "soc" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "soc" {
  name                = "vnet-honeypot"
  location            = azurerm_resource_group.soc.location
  resource_group_name = azurerm_resource_group.soc.name
  address_space       = ["10.0.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "soc" {
  name                 = "subnet-soc"
  resource_group_name  = azurerm_resource_group.soc.name
  virtual_network_name = azurerm_virtual_network.soc.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "soc" {
  name                = "nsg-mini-soc"
  location            = azurerm_resource_group.soc.location
  resource_group_name = azurerm_resource_group.soc.name
  tags                = local.tags
}

# No inbound RDP by default. If deliberately enabled, restrict to a trusted /32 address.
resource "azurerm_network_security_rule" "limited_rdp" {
  count                       = var.create_public_ip && var.allowed_rdp_source != "" ? 1 : 0
  name                        = "Allow-RDP-Trusted-IP-Only"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = var.allowed_rdp_source
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.soc.name
  network_security_group_name = azurerm_network_security_group.soc.name
}

resource "azurerm_subnet_network_security_group_association" "soc" {
  subnet_id                 = azurerm_subnet.soc.id
  network_security_group_id = azurerm_network_security_group.soc.id
}

resource "azurerm_public_ip" "soc" {
  count               = var.create_public_ip ? 1 : 0
  name                = "pip-mini-soc"
  location            = azurerm_resource_group.soc.location
  resource_group_name = azurerm_resource_group.soc.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_network_interface" "soc" {
  name                = "nic-mini-soc"
  location            = azurerm_resource_group.soc.location
  resource_group_name = azurerm_resource_group.soc.name
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.soc.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.create_public_ip ? azurerm_public_ip.soc[0].id : null
  }
  tags = local.tags
}

resource "azurerm_windows_virtual_machine" "soc" {
  name                  = "vm-soc-windows"
  resource_group_name   = azurerm_resource_group.soc.name
  location              = azurerm_resource_group.soc.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.soc.id]
  provision_vm_agent    = true

  # Windows 11 desktop images on Azure require eligible BYOL rights.
  license_type        = "Windows_Client"
  secure_boot_enabled = true
  vtpm_enabled        = true

  # No boot_diagnostics block: disabled, matching the screenshot.

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 127
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = var.windows_image_sku
    version   = "latest"
  }
  tags = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_log_analytics_workspace" "soc" {
  name                = var.workspace_name
  location            = azurerm_resource_group.soc.location
  resource_group_name = azurerm_resource_group.soc.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "soc" {
  workspace_id = azurerm_log_analytics_workspace.soc.id
}

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.soc.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

# Security events go to SecurityEvent (NOT generic Event) via Microsoft-SecurityEvent.
# Collect only failed (4625) and successful (4624) logons to limit lab ingestion costs.

resource "azurerm_monitor_data_collection_rule" "soc" {
  name                = "dcr-soc-windows-security"
  resource_group_name = azurerm_resource_group.soc.name
  location            = azurerm_resource_group.soc.location
  kind                = "Windows"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.soc.id
      name                  = "soc-law"
    }
  }

  data_flow {
    streams      = ["Microsoft-SecurityEvent"]
    destinations = ["soc-law"]
  }

  data_sources {
    windows_event_log {
      name    = "windows-security-events"
      streams = ["Microsoft-SecurityEvent"]

      x_path_queries = [
        "Security!*[System[(EventID=4624 or EventID=4625)]]"
      ]
    }
  }

  tags = local.tags

  depends_on = [
    azurerm_sentinel_log_analytics_workspace_onboarding.soc
  ]

}



resource "azurerm_monitor_data_collection_rule_association" "soc" {
  name                    = "dcra-soc-windows"
  target_resource_id      = azurerm_windows_virtual_machine.soc.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.soc.id
  depends_on              = [azurerm_virtual_machine_extension.ama]
}

resource "azurerm_sentinel_alert_rule_scheduled" "failed_logins" {
  name                       = "mini-soc-failed-logins"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.soc.workspace_id
  display_name               = "Multiple Failed Login Attempts"
  description                = "Lab detection: at least five failed logins on a Windows VM over 15 minutes."
  severity                   = "Medium"
  enabled                    = true
  query_frequency            = "PT5M"
  query_period               = "PT15M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0
  tactics                    = ["CredentialAccess"]
  techniques                 = ["T1110"]
  query                      = <<-KQL
    SecurityEvent
    | where TimeGenerated > ago(15m)
    | where EventID == 4625
    | summarize FailedAttempts=count(), FirstAttempt=min(TimeGenerated), LastAttempt=max(TimeGenerated) by Computer
    | where FailedAttempts >= 5
  KQL

  incident {
    create_incident_enabled = true

    grouping {
      enabled                 = false
      reopen_closed_incidents = false
      lookback_duration       = "PT5M"
      entity_matching_method  = "AllEntities"
    }
  }
}
