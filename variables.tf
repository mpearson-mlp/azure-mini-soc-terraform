variable "subscription_id" {
  description = "Azure subscription UUID. Run: az account show --query id -o tsv"
  type        = string
}
variable "location" {
  description = "Azure deployment region"
  type        = string
  default     = "eastus2"
}
variable "resource_group_name" {
  type    = string
  default = "rg-ai-honeypot"
}
variable "admin_username" {
  type    = string
  default = "azureuser"
}
variable "admin_password" {
  description = "Strong password for the Windows VM; provide via TF_VAR_admin_password, never commit it"
  type        = string
  sensitive   = true
  ephemeral   = false
  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "Choose a password at least 12 characters long."
  }
}
variable "vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}
variable "windows_image_sku" {
  description = "Check availability with az vm image list-skus -l eastus2 -p MicrosoftWindowsDesktop -f windows-11 -o table"
  type        = string
  default     = "win11-25h2-pro"
}
variable "allowed_rdp_source" {
  description = "Optional single trusted public IPv4 CIDR (e.g. 198.51.100.5/32). Leave empty to disable public RDP. Never use 0.0.0.0/0."
  type        = string
  default     = ""
  validation {
    condition     = var.allowed_rdp_source == "" || (can(cidrhost(var.allowed_rdp_source, 0)) && var.allowed_rdp_source != "0.0.0.0/0")
    error_message = "Use a valid restricted IPv4 CIDR or leave this empty. Never expose RDP to everyone."
  }
}
variable "create_public_ip" {
  description = "For controlled direct RDP only. Default false; use a private connectivity method instead."
  type        = bool
  default     = false
}
variable "workspace_name" {
  type    = string
  default = "law-mini-soc-001"
}
