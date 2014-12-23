$subscriptionName = (Get-AzureSubscription).SubscriptionName
$cloudServiceName = "warpigcloud"
$storageAccountName = "warpigstorage"
$imageFamily = "Windows Server 2012 R2 DataCenter"
$imageName = (Get-AzureVMImage | where {$_.ImageFamily -eq $imageFamily} | sort PublishDate -Descending | select -ExcludeProperty ImageName -First 1).ImageName
$vmSize = (Get-AzureRoleSize | where{$_.SupportedByVirtualMachines -eq $true -and  $_.Cores -eq $cores} | select -First 1).InstanceSize
$location = "West US"
$cores = 8

$vmCreateMethod = "New-AzureQuickVM"

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

#unique identifier for VM name
$miniGuid = [guid]::NewGuid().ToString().Split("-")[0]

Switch -exact ($vmCreateMethod)
{
  "New-AzureQuickVM"
  {
    $adminUser = "warpig-admin"
    $password = "Warpig-1@3$"
    $vmName = "warpig-" + $miniGuid
    $vmCreateCommand = $vmCreateMethod + " " + "-Windows -ServiceName $cloudServiceName -Name $vmName -ImageName $imageName -InstanceSize $vmSize -AdminUsername $adminUser -Password $password"
    Invoke-Expression $vmCreateCommand
  }
}
