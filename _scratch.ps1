#Select-AzureSubscription -SubscriptionName $subscriptionName


#Get-AzureVM -ServiceName $cloudServiceName -Name $vmName | Remove-AzureDataDisk -LUN 1 | Update-AzureVM
#Remove-AzureDisk -DiskName $diskName -DeleteVHD

#Remove-CloudService -CloudServiceName $cloudServiceName
#Remove-StorageAccount $storageAccountName


#Remove-AzureDisk -DiskName $diskName -DeleteVHD

#unique identifier for VM names
$miniGuid = [guid]::NewGuid().ToString().Split("-")[0]

#variables
$subscriptionName = (Get-AzureSubscription).SubscriptionName
$cloudServiceName = "warpigcloud"
$storageAccountName = "warpigstorage"
$imageFamily = "Windows Server 2012 R2 DataCenter"
$imageName = (Get-AzureVMImage | where {$_.ImageFamily -eq $imageFamily} | sort PublishDate -Descending | select -ExcludeProperty ImageName -First 1).ImageName
$vmSize = (Get-AzureRoleSize | where{$_.SupportedByVirtualMachines -eq $true -and  $_.Cores -eq $cores} | select -First 1).InstanceSize
$location = "West US"
$cores = 8
$vmName = "warpig-" + $miniGuid
$adminUser = "warpig-admin"
$password = "Warpig-1@3$"
$diskSize = ((Get-AzureRoleSize | where{$_.InstanceSize -eq $vmSize}).VirtualMachineResourceDiskSizeInMb)/1000

$diskName = "warpig-disk-001"
$uploadSource = "\\vmware-host\Shared Folders\viresh001\azure-war-pig\$diskName.vhd"
$uploadDestination = "https://$storageAccountName.blob.core.windows.net/upload/$diskName.vhd"

$downloadSource = "https://$storageAccountName.blob.core.windows.net/upload/$diskName.vhd"
$downloadDestination = "\\vmware-host\Shared Folders\viresh001\azure-war-pig\$diskName.vhd"


#get Azure subscription credentials if needed
#Add-AzureAccount

#pipe Get-AzureSubscription into Select-AzureSubscription
Get-AzureSubscription | Select-AzureSubscription

Get-AzureVMImage

#set CurrentStorageAccountName if needed
if((Get-AzureSubscription).CurrentStorageAccountName -ne $storageAccountName)
{
  Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccountName $storageAccountName
}

#create CloudService if needed
if((Test-AzureName -Service -Name $cloudServiceName) -eq $false)
{
  New-AzureService $cloudServiceName -Location $location
}


#make new VM #TODO need function for this
$vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize $vmSize -ImageName $imageName
$vmConfig | Add-AzureProvisioningConfig -Windows -AdminUsername $adminUser -Password $password
$vmConfig | Add-AzureEndpoint -Name "HTTP" -Protocol tcp -LocalPort 80 -PublicPort 80 -LBSetName "LBHTTP" -DefaultProbe
$vmConfig | Add-AzureEndpoint -Name "HTTPS" -Protocol tcp -LocalPort 443 -PublicPort 443 -LBSetName "LBHTTPS" -DefaultProbe
    
New-AzureVM -ServiceName $cloudServiceName -VMs $vmConfig

Add-AzureVhd -LocalFilePath $uploadSource -Destination $uploadDestination -OverWrite

#associate vhd files with diskName
if(!((Get-AzureDisk) | where DiskName -eq $diskName))
{
  Add-AzureDisk -DiskName $diskName -MediaLocation $uploadDestination
}

Get-AzureVM -ServiceName $cloudServiceName -Name $vmName | Add-AzureDataDisk -Import -Diskname $diskName -LUN 1 | Update-AzureVM

Get-AzureRemoteDesktopFile -ServiceName $cloudServiceName -Name $vmName -Launch

Save-AzureVhd -Source $downloadSource -LocalFilePath $downloadDestination -OverWrite



Function Remove-OrphanDisks($diskNamePattern)
{
  $diskList = Get-AzureDisk | where{$_.MediaLink -match "$diskNamePattern"} -ErrorAction Stop
  foreach($disk in $diskList)  {
    while($disk | where {$_.AttachedTo -ne $null})  {
      Start-Sleep -Seconds 30
    }
    Remove-AzureDisk -DiskName $disk.DiskName -DeleteVHD -ErrorAction Stop
  }
}

Function Remove-CloudService($csNamePattern)
{
  $csList = Get-AzureService | where{$_.ServiceName -match $csNamePattern} -ErrorAction Stop
  foreach($cloudService in $csList)  {
    $cloudService | Remove-AzureService -DeleteAll -Force -ErrorAction Stop
  }
}
  


#pipe Get-AzureSubscription into Select-AzureSubscription
Get-AzureSubscription | Select-AzureSubscription

Remove-CloudService("warpig-cloud-cert2")

Remove-OrphanDisks("warpig")


#write-host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
#write-host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red


$miniGuid = [guid]::NewGuid().ToString().Split("-")[0]


$adminUser = "warpig-admin"
$password = "Warpig-1@3$"
$location = "West US"
$cloudServiceName = "warpigcloud-XXX"# + $miniGuid
$vmName = "warpig-XXX"# + $miniGuid
$cores = 8
$vmSize = (Get-AzureRoleSize | where{$_.SupportedByVirtualMachines -eq $true -and  $_.Cores -eq $cores} | select -First 1).InstanceSize
$imageFamily = "Windows Server 2012 R2 DataCenter"
$imageName = Get-AzureVMImage | where {$_.ImageFamily -eq $imageFamily} | sort PublishDate -Descending | select -ExpandProperty ImageName -First 1



Function Remove-CloudService($csNamePattern)
{
  $csList = Get-AzureService | where{$_.ServiceName -match $csNamePattern} -ErrorAction Stop
  foreach($cloudService in $csList)  {
    $cloudService | Remove-AzureService -DeleteAll -Force -ErrorAction Stop
  }
}


Function Customize-VirtualMachine()
{
}

Function Quick-CreateVM()
{
  New-AzureQuickVM -Windows -ServiceName "warpigcloud-eb941104" -Name $vmName -ImageName $vmName <#-Location $location#> -AdminUsername $adminUser -Password $password -InstanceSize $vmSize -WaitForBoot -ErrorAction Stop
}

Function Save-CustomVM()
{
  Save-AzureVMImage -ServiceName "warpigcloud-eb941104" -Name "warpig-eb941104" -NewImageName $vmName -NewImageLabel $vmName -OSState Generalized
}




#pipe Get-AzureSubscription into Select-AzureSubscription
Get-AzureSubscription | Select-AzureSubscription

Quick-CreateVM

#Save-CustomVM

#Get-AzureRemoteDesktopFile -ServiceName $cloudServiceName -Name $vmName -Launch -ErrorAction Stop

