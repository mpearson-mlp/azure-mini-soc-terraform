output "resource_group" {
  value = azurerm_resource_group.soc.name
}
output "vm_name" {
  value = azurerm_windows_virtual_machine.soc.name
}
output "vm_private_ip" {
  value = azurerm_network_interface.soc.private_ip_address
}
output "vm_public_ip" {
  value = var.create_public_ip ? azurerm_public_ip.soc[0].ip_address : null
}
output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.soc.name
}
output "sentinel_workspace_id" {
  value = azurerm_sentinel_log_analytics_workspace_onboarding.soc.workspace_id
}
