function Create-SCVirtualMachineWithDiffDisk
{

<#
.SYNOPSIS
This function will create one or more SCVMM 2012 VMs that use a differencing disk.

.DESCRIPTION
This function will allow an administrator to create new SCVMM 2012 VMs that use differencing disks and parent disks.
In order to execute the script, you must ensure that Windows Remote Management has been configured properly on the VMM Server and any VM Hosts.
CredSSP authentication must also be enabled on both the client machine executing the script and the VMM Server if a credential is passed.*

.PARAMETER VMMServer
The name of the VMM Server. Defaults to localhost. Must be a string.

.PARAMETER VM
Friendly name of the virtual machine to be created. Must be a string.

.PARAMETER Template
Name of the VMM template from which to create the virtual machine. Must be a string.

.PARAMETER HardwareProfile
Name of the VMM hardware profile from which to create the virtual machine. Must be a string.

.PARAMETER Cloud
Name of the VMM cloud on which the virtual machine will be placed if the VMHost parameter is not specified.
Either the Cloud parameter or the VMHost parameter must be specified. Both cannot be used. Must be a string.

.PARAMETER VMHost
Name of the host on which the virtual machine will be placed if the Cloud parameter is not specified.
Either the Cloud parameter or the VMHost parameter must be specified. Both cannot be used. Must be a string.

.PARAMETER Credential
Credential object used for authentication to the VMM Server and target hosts.

.EXAMPLE
Create-SCVirtualMachineWithDiffDisk -VM "NewVM01" -Template "Server 2012" -HardwareProfile "Server 2012" -Cloud "Server"

This command allows you to create a VM named "NewVM01" with a differencing disk. The VM is based on the  "Server 2012" template,
"Server 2012" hardware profile, and "Server" cloud.

.EXAMPLE
$cred = Get-Credential
Create-SCVirtualMachineWithDiffDisk -VMName "NewVM01" -TemplateName "Server 2012 Template" -HardwareProfileName "Server 2012" -Cloud "Server" -Credential $cred

This command allows you to create a VM named "NewVM01" with a differencing disk. The VM is based on the  "Server 2012" template,
"Server 2012" hardware profile, and "Server" cloud. The $cred variable is then passed in as a Credential which contains a credential object.

.NOTES
Author:  Andrew Weiss
Email:   andrew.weiss@microsoft.com
Date:    10/25/2012
Version: 1.0

*To enable CredSSP authentication and quickly configure Windows Remote Management
execute the following commands using an administrative Powershell Console:
On the client machine -> Enable-WSManCredSSP -Role Client -DelegateComputer "<FQDN of VMM Server>"
On the VMM Server -> winrm quickconfig; Enable-WSManCredSSP -Role Server
On the target host(s) -> winrm quickconfig
#>

    [CmdletBinding()]

    param
    (
	    [Parameter(Position=0,ValueFromPipeline=$true)]
	    [string]$VMMServer = "localhost",
        [Parameter(Mandatory=$true)]
        [alias("VM","VirtualMachineName")]
	    [string[]]$VMName,
        [alias("Template")]
	    [string]$TemplateName,
        [alias("HardwareProfile")]
	    [string]$HardwareProfileName,
        [string]$Cloud,
	    [string]$VMHost,
	    [System.Management.Automation.PSCredential]$Credential
    )

    begin
    {
        $tempErrAction = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
    }

    process
    {
        
        if ($Cloud -ne "" -and $VMHost -ne "") { throw "You cannot specify both a Cloud and a Host when executing this cmdlet" }

        try
        {
            # Check to see if VMM Module has been loaded
            # If not, load it
            Write-Output "Checking to see if the VirtualMachineManager module has been loaded..."
            $vmmModule = "virtualmachinemanager"
            if (!(Get-Module | ? {$_.Name -eq $vmmModule}))
            {
                if (Get-Module -ListAvailable | ? {$_.Name -eq $vmmModule}) { Import-Module -Name $vmmModule }
                else { throw "You do not have the Virtual Machine Manager PowerShell module installed on your system" }
            }
                
            Write-Output "Module loaded successfully"

            if ($VMName -eq $null) { throw "The VMName to create has not been specified" }
                
            # Obtain VMM Hardware Profile Object
            $hardwareProfile = Get-SCHardwareProfile -VMMServer $VMMServer  | ? {$_.Name -eq $HardwareProfileName}
            if ($hardwareProfile -eq $null) { throw "Cannot obtain the specified hardware profile"; exit 1 }

            # Obtain VMM VM Template Object
            $template = Get-SCVMTemplate -VMMServer $VMMServer -All | ? {$_.Name -eq $TemplateName}
            if ($template -eq $null) { throw "Cannot obtain the specified template" }

            # Obtain VHD information from the template
            $VHD =  Get-SCVirtualharddisk | ? {$_.Name -eq $template.VirtualDiskDrives[0].VirtualHardDisk}
        }
        catch { throw $_ }

        foreach ($VM in $VMName)      
        {
            try
            {
                Write-Output "Creating the $VM virtual machine"
                Write-Output "Obtaining the appropriate information from VMM..."

                # Select a random host object if a cloud is specified in the cmdlet
                if ($Cloud -ne $null)
                {
                    $cloudObject = Get-SCCloud "$Cloud"
                    if ($cloudObject -eq $null) { throw "Cannot obtain the specified cloud" }

                    # Select a random host group object from the cloud
                    $hostGroup = $cloudObject.HostGroup
                    
                    # VHD Size in GB
                    $VHDSize = $VHD.size/1073741824

                    # Obtain host ratings and sort them highest to lowest
                    $hostRatings = Get-SCVMHostRating -VMHostGroup $hostGroup -Template $template -DiskSpaceGB $VHDSize -VMName $VM | Sort-Object -Descending Rating

                    # If any hosts have a 0 rating, error out
                    if ($hostRatings[0].Rating -eq 0)
                    {
                        throw "No hosts in the $CloudName cloud are available for placement"
                    }

                    # Determine any hosts with equal ratings
                    $equalHostRatings = 1
                    for ($r = 1; $r -le $hostRatings.count; $r++)
                    {
                        if ($hostRatings[0].Rating -eq $hostRatings[$r].Rating)
                        {
                            $equalHostRatings++
                        }
                    }

                    # If any hosts have equal ratings, get a random host object
                    if ($equalHostRatings -gt 1)
                    {
                        $randomHost = Get-Random -Maximum $equalHostRatings
                        $vmHostObject = Get-SCVMHost -ComputerName $hostRatings[$randomHost].Name
                    }
                    else
                    {
                        $vmHostObject = Get-SCVMHost -ComputerName $hostRatings[0].Name
                    }
                    
                }
                elseif ($VMHost -ne $null)
                {
                    $vmHostObject = Get-SCVMHost $VMHost
                }
                else
                {
                    throw "You must specify either a cloud or a host to which $VM will be deployed"
                }
                
                $VMHost = $vmHostObject.Name

                
                if ($vmHostObject -eq $null)
                {
                    throw "Cannot obtain the specified host information"
                }

                # Set the default paths for the VMs and their VHDs
                # $vmHostObject.vmpaths is an array and must be indexed properly in this variable
                # if multiple Virtual Machine Paths exist for this particular host in VMM
                # i.e. [string]$vmHostObject.vmpaths[3]
                $vmHostBasePath = [string]$vmHostObject.vmpaths + "\"
                $vmHostParentVHDPath = $vmHostBasePath + "ParentVHDs\"
                $vmHostPath = $vmHostBasePath
                $vmHostDiffVHDPath = $vmHostBasePath + "DiffVHDs\"
                
                if ($Credential -eq $null)
                {
                    $invokeCommandSplat = @{'ComputerName'=$VMHost}
                }
                else
                {
                    $invokeCommandSplat = @{'ComputerName'=$VMHost;'Authentication'='CredSSP';'Credential'=$Credential}
                }
                
                # Command invocation which creates directories as necessary on the target host
                # and copies the parent VHD if it does not exist
                Invoke-Command @invokeCommandSplat -ScriptBlock {
                    param($vmHostDiffVHDPath, $vmHostParentVHDPath, $VHD)
        
                    # Check to see if folder to place differencing and parent disk VHDs exist
                    # and if not, create the directory(s)
                    if (!(Test-Path "$vmHostDiffVHDPath"))
                    {
                        New-Item "$vmHostDiffVHDPath" -type Directory | Out-Null
                    }
                    if (!(Test-Path "$vmHostParentVHDPath"))
                    {
                        New-Item "$vmHostParentVHDPath" -type Directory | Out-Null
                    }

                    $vmHostParentVHDPath = $vmHostParentVHDPath + [system.io.path]::GetFileName($VHD.SharePath);

                    Write-Output "Checking to see if the parent VHD file exists on the target host..."                            
                    
                    # Check to see if the parent VHD exists on the host
                    # and if it doesn't, copy the parent VHD from the VMM Library
                    # to the host (multi-hop authentication utilized here)
                    if (!(Test-Path $vmHostParentVHDPath))
                    {
                        Write-Output "Parent VHD does not exist...copying now"
	                    [System.IO.File]::Copy($VHD.SharePath,$vmHostParentVHDPath)
                        Write-Output "Parent VHD file copied to the target host successfully"
                    }
                    else
                    {
                        Write-Output "Parent VHD file already exists on the host"
                    }
                } -argumentlist $vmHostDiffVHDPath, $vmHostParentVHDPath, $VHD

                # Set the variables for the paths to both the parent VHD and the new child VHD
                $parentVHDPath = $vmHostParentVHDPath + [system.io.path]::GetFileName($VHD.SharePath)
                $targetVHDPath = $vmHostDiffVHDPath + $VM + ".vhd"
                
                if (Test-Path "$targetVHDPath")
                {
                    throw "The differencing disk for $VM already exists. Check to make sure $VM has not previously been created"
                }

                # Command invocation to create the differencing disk on the target VM host
                Invoke-Command @invokeCommandSplat -ScriptBlock {
                    param($VMHost, $targetVHDPath, $parentVHDPath)
        
                    # Initialize function to create the differencing disk on the host
                    function CreateDiffDiskOnHost
                    {
                        param
                        (
                            [string]$hostComputerName, [string]$childPath, [string]$parentPath
                        )

                        # Get the image mgmt service instance for the host computer
                        $VHDService = gwmi -Class "Msvm_ImageManagementService" -Namespace "root\virtualization"
                    
                        # Create the child differencing disk from the parent disk
                        $Result = $VHDService.CreateDifferencingVirtualHardDisk($childPath, $parentPath)
                    }

                    Write-Output "Creating the differencing disk on the target host..."
                    
                    CreateDiffDiskOnHost "$VMHost" "$targetVHDPath" "$parentVHDPath"
                    
                    # Pause script for 20 seconds
                    Start-Sleep -s 10
                    
                    if (Test-Path $targetVHDPath)
                    {
                        Write-Output "Successfully created the differencing disk on the target host..."
                    }
                    else
                    {
                        throw "Failed to create differencing disk on the target host"
                    }
                } -argumentlist $VMHost, $targetVHDPath, $parentVHDPath

                # Set a random startup delay to reduce VM startup IOPs overload
                $startDelay = Get-Random -minimum 1 -maximum 30

                # Command invocation that tests to make sure that the differencing disk VHD file isn't locked
                Invoke-Command @invokeCommandSplat -ScriptBlock {
                    param($targetVHDPath)
    
                    function TestFileLock
                    {
                        # Attempts to open a file and trap the resulting error if the file is already open/locked
                        param ([string]$filePath)

                        $filelocked = $false;
                        $fileInfo = New-Object System.IO.FileInfo $filePath
                        trap
                        {
                            Set-Variable -name locked -value $true -scope 1
                            continue
                        }
                        $fileStream = $fileInfo.Open( [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None )
                        if ($fileStream)
                        {
                            $fileStream.Close()
                        }
                        $obj = New-Object Object
                        $obj | Add-Member Noteproperty FilePath -value $filePath
                        $obj | Add-Member Noteproperty IsLocked -value $filelocked
                        $obj
                    }
                    
                    Write-Output "Testing the VHD file to ensure that it is not locked for use..."
                    $lockstate = TestFileLock "$targetVHDPath"
                    if ($lockstate.IsLocked) { Start-Sleep -s 30 }

                } -argumentlist $targetVHDPath

                Write-Output "Creating the virtual machine..."

                # Instantiate new GUID
                $guid = [guid]::NewGuid()

                # Assign the appropriate VHD and create the new VM
                $mv = Move-SCVirtualHardDisk -Bus 0 -Lun 0 -IDE -Path $targetVHDPath  -JobGroup $guid
                $description = $template.tag
                if (New-SCVirtualMachine -Name $VM -VMHost $vmHostObject -VMTemplate $template -UseLocalVirtualHardDisk -HardwareProfile $hardwareProfile -ComputerName $VM -Path $vmHostPath -DelayStartSeconds $startDelay  -Description "$description" -MergeAnswerFile $true -BlockDynamicOptimization $false -StartVM -JobGroup "$guid" -RunAsynchronously -StartAction "AlwaysAutoTurnOnVM" -StopAction "SaveVM")
                {
                    Write-Output "The virtual machine creation process for $VM has been successfully initiated"
                }
                else { throw "The virtual machine creation process for $VM could not be successfully initiated" }
            }
            catch
            {
                if ($_ -like "*Copy*Access*denied*") { throw "Access to the VHD Share path on the VMM Library Server is denied. Try executing the cmdlet with credentials" }
                
                Write-Error $_
            }
        }
    }
    end
    {
        $ErrorActionPreference = $tempErrAction
    }
} #end function