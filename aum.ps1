Login-AzAccount

$location = "swedencentral"
$resourceGroupName = "rg-virtualmachines"

$username = "vmuser"
$plainTextPassword = (New-Guid).ToString() + (New-Guid).ToString().ToUpper()
$plainTextPassword
$password = ConvertTo-SecureString -String $plainTextPassword -AsPlainText

$plainTextPassword > .env

# Verify the context
Get-AzContext

# Get the subscription ID
$subscriptionId = (Get-AzContext).Subscription.Id

# Create a resource group
New-AzResourceGroup -Name $resourceGroupName -Location $location -Force

# Create a new virtual network with a subnet
$virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Name "vnet" -Location $location -AddressPrefix "10.0.0.0/16" -Force

# Add NSG to the subnet
$myip = Invoke-WebRequest "https://myip.jannemattila.com" | Select-Object -exp Content

$networkSecurityGroup = New-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Location $location -Name "nsg" -Force

$networkSecurityGroup | Add-AzNetworkSecurityRuleConfig `
    -Name                     "Allow-RDP" `
    -Priority                 100 `
    -Direction                "Inbound" `
    -Access                   "Allow" `
    -Protocol                 "Tcp" `
    -SourceAddressPrefix      $myip `
    -SourcePortRange          "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange     3389

$networkSecurityGroup | Add-AzNetworkSecurityRuleConfig `
    -Name                     "Allow-SSH" `
    -Priority                 200 `
    -Direction                "Inbound" `
    -Access                   "Allow" `
    -Protocol                 "Tcp" `
    -SourceAddressPrefix      $myip `
    -SourcePortRange          "*" `
    -DestinationAddressPrefix "*" `
    -DestinationPortRange     22

# Apply the changes to the NSG
$networkSecurityGroup | Set-AzNetworkSecurityGroup

Add-AzVirtualNetworkSubnetConfig -Name "subnet" -AddressPrefix "10.0.0.0/24" -VirtualNetwork $virtualNetwork -NetworkSecurityGroup $networkSecurityGroup
$virtualNetwork | Set-AzVirtualNetwork

# Create a new Windows Server VM
$windowsVMName = "vm-win"
$linuxVMName = "vm-linux"
$vmSize = "Standard_B2s"
$credentials = New-Object System.Management.Automation.PSCredential ($username, $password)

New-AzVm `
    -Name $windowsVMName `
    -ResourceGroupName $resourceGroupName `
    -Size $vmSize `
    -Location $location `
    -Credential $credentials `
    -Image "MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest" `
    -VirtualNetworkName "vnet" `
    -SubnetName "subnet" `
    -SecurityGroupName "nsg" `
    -PublicIpAddressName "pip-win"

New-AzVm `
    -Name $linuxVMName `
    -ResourceGroupName $resourceGroupName `
    -Size $vmSize `
    -Location $location `
    -Credential $credentials `
    -Image Ubuntu2204 `
    -VirtualNetworkName "vnet" `
    -SubnetName "subnet" `
    -SecurityGroupName "nsg" `
    -PublicIpAddressName "pip-linux"

# Create maintenance configuration
$testMaintenanceConfiguration = New-AzMaintenanceConfiguration `
    -Name "TestMaintenanceConfiguration" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -MaintenanceScope "InGuestPatch" `
    -Duration "03:00" `
    -Timezone "FLE Standard Time" `
    -RecurEvery "1Week Wednesday" `
    -StartDateTime "2024-10-10 01:00" -ExtensionProperty @{"InGuestPatchMode" = "Platform" }
$testMaintenanceConfiguration
$testMaintenanceConfiguration.Id

$productionMaintenanceConfiguration = New-AzMaintenanceConfiguration `
    -Name "ProductionMaintenanceConfiguration" `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -MaintenanceScope "InGuestPatch" `
    -Duration "03:00" `
    -Timezone "FLE Standard Time" `
    -RecurEvery "1Week Saturday" `
    -StartDateTime "2024-10-10 01:00" -ExtensionProperty @{"InGuestPatchMode" = "Platform" }
$productionMaintenanceConfiguration
$productionMaintenanceConfiguration.Id

# ------------

# Configure periodic checking for missing system updates on azure Arc-enabled servers
# - Note: OS specific policy assingment
# - Tags:
# {"environment": "Development"}

# Machines should be configured to periodically check for missing system updates
# - Audits if the machines are configured to periodically check for missing system updates

# Schedule recurring updates using Azure Update Manager
# - Tags:
# [ {"key": "environment", "value": "Development"}, {"key": "environment", "value": "Test"}]
# [ {"key": "environment", "value": "Production"} ]

# [Preview]: Set prerequisite for Scheduling recurring updates on Azure virtual machines.

# Configure periodic checking for missing system updates on azure virtual machines
# - Note: OS specific policy assingment
# - Tags:
# {"environment": "Development"}

$aumPolicies = Get-AzPolicyDefinition | Where-Object { $_.Metadata.Category -eq "Azure Update Manager" } 
$aumPolicies | Format-List

Start-AzPolicyComplianceScan -ResourceGroupName $resourceGroupName
