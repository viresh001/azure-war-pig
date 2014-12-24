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
$diskLabel = "warpig-disk-" + $miniGuid
$adminUser = "warpig-admin"
$password = "Warpig-1@3$"
$diskSize = ((Get-AzureRoleSize | where{$_.InstanceSize -eq $vmSize}).VirtualMachineResourceDiskSizeInMb)/1000

$vmCreateMethod = "New-AzureVM"

#get Azure subscription credentials if needed
#Add-AzureAccount

#pipe Get-AzureSubscription into Select-AzureSubscription
Get-AzureSubscription | Select-AzureSubscription

#create StorageAccunt if needed
if ((Test-AzureName -Storage -Name $storageAccountName) -eq $false)
{
  New-AzureStorageAccount -StorageAccountName $storageAccountName -Location $location
}

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

#handle different VM creation methods
Switch -exact ($vmCreateMethod)
{
  "New-AzureQuickVM"
  {
    $vmCreateMethod = $vmCreateMethod + " -Windows -ServiceName $cloudServiceName -Name $vmName -ImageName $imageName -InstanceSize $vmSize -AdminUsername $adminUser -Password $password"
    Invoke-Expression $vmCreateMethod
  }
  "New-AzureVM"
  {
    $vmConfig = New-AzureVMConfig -Name $vmName -InstanceSize $vmSize -ImageName $imageName
    $vmConfig | Add-AzureProvisioningConfig -Windows -AdminUsername $adminUser -Password $password
    $vmConfig | Add-AzureDataDisk -CreateNew -DiskSizeInGB $diskSize -DiskLabel $diskLabel -LUN 0
    $vmConfig | Add-AzureEndpoint -Name "HTTP" -Protocol tcp -LocalPort 80 -PublicPort 80 -LBSetName "LBHTTP" -DefaultProbe
    $vmConfig | Add-AzureEndpoint -Name "HTTPS" -Protocol tcp -LocalPort 443 -PublicPort 443 -LBSetName "LBHTTPS" -DefaultProbe
    
    New-AzureVM -ServiceName $cloudServiceName -VMs $vmConfig

    $vmConfig = Get-AzureVM -ServiceName $cloudServiceName -Name $vmName
    if($vmConfig | Get-AzureEndpoint | where Name -eq "RemoteDesktop")
    {
      $vmConfig | Remove-AzureEndpoint -Name "RemoteDesktop"
      $vmConfig | Update-AzureVM
    }

    $vmConfig = Get-AzureVM -ServiceName $cloudServiceName -Name $vmName
    if(!($vmConfig | Get-AzureEndpoint | where Name -eq "RemoteDesktop"))
    {
      $vmConfig | Add-AzureEndpoint -Name "RemoteDesktop" -Protocol tcp -LocalPort 3389
      $vmConfig | Update-AzureVM
      Get-AzureRemoteDesktopFile -ServiceName $cloudServiceName -Name $vmName -Launch
    }
  }
}

Get-AzureVM -ServiceName $cloudServiceName | Stop-AzureVM -Force
Remove-AzureService -ServiceName $cloudServiceName  -Force

