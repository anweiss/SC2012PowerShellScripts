# ==============================================================================================
#
# NAME: ClearDormantCustomPropertyValues
# 
# AUTHOR: Andrew Weiss
# DATE  : 10/4/2012
# 
# ==============================================================================================

<#

.SYNOPSIS
This script allows you to clear the "isDormant" and "Dormant Date" custom property values

.DESCRIPTION
The ClearDormantCustomPropertyValues.ps1 script allows you to specificy a VMM Server and VMs from which you want to remove existing dormant custom property values

.PARAMETER VMMServer
The System Center Virtual Machine Manager 2012 Server

.PARAMETER VM
The name(s) of the VM(s) from which you want to clear the custom property values

.PARAMETER Credential
The credentials to use when connecting to the VMM server. This can be set using the Get-Credential CmdLet.

.EXAMPLE
ClearDormantCustomPropertyValues.ps1 -VMMServer contosovmm.contoso.com -VM "MyVM01"

This command will connect to the "contosovmm.contoso.com" VMM Server and clear the custom property values from "MyVM01" VM.

.EXAMPLE
ClearDormantCustomPropertyValues.ps1 -VMMServer contosovmm.contoso.com -VM MyVM01, MyVM02

This command will connect to the "contosovmm.contoso.com" VMM Server and clear the custom property values from "MyVM01" and "MyVM02" VMs

.EXAMPLE
$cred = Get-Credential
C:\PS> ClearDormantCustomPropertyValues.ps1 -VMMServer contosovmm.contoso.com -VM MyVM01, MyVM02 -Credential $cred

This will do the exact same action as the previous example, but it will use the passed credentials.

#>

# Define script parameters
param
(
    [Parameter(Mandatory=$false,Position=0)]
    [string]$VMMServer = "localhost",
    [Parameter(Mandatory=$true,Position=1)]
	[string[]]$VM,
    [Parameter(Mandatory=$false,Position=2)]
    $Credential
)

# Define the trap
trap
{
	Write-Error -Message $_
	exit 1
}

# Check to see if Virtual Machine Manager Module is loaded
$vmmModule = "virtualmachinemanager"
if (!(Get-Module | ? {$_.Name -eq $vmmModule})) {
    if (Get-Module -ListAvailable | ? {$_.Name -eq $vmmModule}) {
        Import-Module -Name $vmmModule
    }
    else {
        throw "You do not have the Virtual Machine Manager PowerShell module installed on your system"
    }
}

# Connect to the VMM Server
if ($Credential -ne $null)
{
	# Connect to the VMM server with credentials
	$vmmConnection = Get-SCVMMServer -ComputerName $VMMServer -Credential $Credential
}
else
{
	# Connect to the VMM server without credentials
	$vmmConnection = Get-SCVMMServer -ComputerName $VMMServer
}

# Initialize custom property object variables
$customPropIsDormant = Get-SCCustomProperty -Name "isDormant"
$customPropDormantDate = Get-SCCustomProperty -Name "Dormant Date"

# Loop through each of the VMs specified and clear the custom property values
if ($VM -ne $null) {
    foreach ($vmName in $VM) {
    
        # Check for existence of VM specified
        if (!($virtualMachine = Get-SCVirtualMachine -Name $vmName)) { Write-Host "$vmName does not exist"; exit 1 }
        
        $isDormantValue = Get-SCCustomPropertyValue -CustomProperty $customPropIsDormant -InputObject $virtualMachine
        if ($isDormantValue -ne $null) {
            Remove-SCCustomPropertyValue -CustomPropertyValue $isDormantValue | Out-Null
        }
        $dormantDateValue = Get-SCCustomPropertyValue -CustomProperty $customPropDormantDate -InputObject $virtualMachine
        if ($dormantDateValue -ne $null) {
            Remove-SCCustomPropertyValue -CustomPropertyValue $dormantDateValue | Out-Null
        }
        Write-Host "$vmName's custom properties have been successfully cleared"
    }
}
else {
    throw "No VMs were specified"
}
