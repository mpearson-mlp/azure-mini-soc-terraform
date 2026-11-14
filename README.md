# Azure Cloud Mini SOC — Terraform

Creates the Azure Mini SOC: resource group, VNet/subnet/NSG, Windows 11 Pro 25H2 Gen2 VM (2 vCPU/8 GiB, Standard SSD, Trusted Launch), Log Analytics, Microsoft Sentinel onboarding, Azure Monitor Windows Agent (AMA), Data Collection Rule (DCR) streaming Security Event IDs 4624 and 4625 to `SecurityEvent`, and a scheduled Sentinel alert rule for 5+ failed logins within 15 minutes.

## Prerequisites
- Azure CLI logged in (`az login`) with permission to provision the resources and configure Sentinel.
- Terraform >= 1.5; AzureRM provider 4.x.
- Windows 11 desktop BYOL eligibility; image availability in your Azure region and available Standard_D2s_v3 quota.
- A secure access solution to the VM. **No public IP and no inbound RDP rule are created by default.** For interactive access use an existing private network/VPN or configure Azure Bastion separately (Bastion has extra fees and subnet requirements).
- No live resources are deployed by downloading these files.

## Deploy
```bash
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars subscription_id
export TF_VAR_admin_password='REPLACE-WITH-A-LONG-UNIQUE-PASSWORD'
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=soc.tfplan
terraform apply soc.tfplan
```

**Security:** Terraform state may contain secrets including the VM password even if the variable is marked sensitive. Keep `terraform.tfstate` in a secured local directory or secured remote backend, and NEVER commit state, variables with passwords, or plans to GitHub. A shell environment variable avoids putting the password in source files, but doesn't remove it from Terraform state.

## Verify logging
In Azure > Log Analytics workspace > Logs, run the queries in `queries.kql` **one at a time**. On the Windows VM, test a wrong password to generate Event ID 4625; you can verify it under Event Viewer > Windows Logs > Security. The Sentinel analytics rule checks every 5 minutes and may need additional ingestion time.

## Access
By default the VM is private to minimize risk. You must provision a secure VM access mechanism separately if none exists. If you intentionally need direct RDP for a short test, set `create_public_ip = true` and `allowed_rdp_source = "YOUR-PUBLIC-IP/32"`. Direct RDP is riskier and may incur public IP charges. Never use `0.0.0.0/0`.

## Important notes
- `win11-25h2-pro` is a Windows 11 Marketplace image SKU seen in catalog lists, but availability and BYOL rights must be checked for your subscription and region. Verify using:
  `az vm image list-skus --location eastus2 --publisher MicrosoftWindowsDesktop --offer windows-11 --output table`
- Azure Monitor Windows Agent installation and DCR association may take time. The DCR uses the Sentinel `Microsoft-SecurityEvent` stream; do not also create a duplicate connector DCR for the same source.
- The code does not automatically install the optional Content Hub solution UI item; it provisions the underlying security-event ingestion path. For portal-level connector/solution status, check in Sentinel and install **Windows Security Events** in Content Hub if needed.
- This package does not set up Azure Bastion, outbound NAT, or a VPN. Ensure that the VM can reach Azure Monitor endpoints to send data; networks using default outbound connectivity may require explicit outbound egress configuration depending on subscription and Azure networking defaults.
- The 127 GiB disk is explicitly set to match the image-default shown in the screenshot; check the selected marketplace image's minimum OS disk size. Windows client license charges may be distinct from the Azure price estimate.
- Terraform does not enable OS guest diagnostics, recommended alerts, or boot diagnostics.

## Clean up
```bash
terraform destroy
```
Review resources and costs even after destroy; confirm resources are gone in Azure Portal. Repeated deployments cost money. **Destroy permanently deletes VM data and lab configuration**.
