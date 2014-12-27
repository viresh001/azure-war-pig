$miniGuid = [guid]::NewGuid().ToString().Split("-")[0]
$subscriptionName = (Get-AzureSubscription).SubscriptionName
$storageAccountName = "warpigstorecert" #+ $miniGuid
$cloudServiceName = "warpig-cloud-cert" #+ $miniGuid
$vmName = "warpig-cert" #+ $miniGuid
$location = "West US"

$cores = 8
$vmSize = (Get-AzureRoleSize | where{$_.SupportedByVirtualMachines -eq $true -and  $_.Cores -eq $cores} | select -First 1).InstanceSize
$imageFamily = "Windows Server 2012 R2 DataCenter"
$imageName = Get-AzureVMImage | where {$_.ImageFamily -eq $imageFamily} | sort PublishDate -Descending | select -ExpandProperty ImageName -First 1

$adminUser = "warpig-admin"
$password = "Warpig-1@3$"

$diskName = "warpig-disk-cert"
$diskSource = "\\vmware-host\Shared Folders\viresh001\azure-war-pig\$diskName.vhd"
$diskDestination = "https://$storageAccountName.blob.core.windows.net/upload/$diskName.vhd"

Function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}

Function Set-AzureSubscription
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $SubscriptionName
  )

  Select-AzureSubscription -SubscriptionName $SubscriptionName
}

Function Create-StorageAccount
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $SubscriptionName, 

    [Parameter(Mandatory=$True)]
    [string] $StorageAccountName,

    [Parameter(Mandatory=$True)]
    [string] $Location
  )

  #create StorageAccunt if needed
  if ((Test-AzureName -Storage -Name $StorageAccountName -ErrorAction Stop) -eq $false)
  {
    New-AzureStorageAccount -StorageAccountName $StorageAccountName -Location $Location -ErrorAction Stop
  }
  Azure\Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccountName $StorageAccountName
}

Function Create-CloudService
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $CloudServiceName, 

    [Parameter(Mandatory=$True)]
    [string] $Location
  )

  #create CloudService if needed
  if((Test-AzureName -Service -Name $CloudServiceName -ErrorAction Stop) -eq $false)
  {
    New-AzureService $CloudServiceName -Location $Location -ErrorAction Stop
  }
}

Function Add-Disk()
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $StorageAccountName,

    [Parameter(Mandatory=$True)]
    [string] $CloudServiceName,

    [Parameter(Mandatory=$True)]
    [string] $VMName,

    [Parameter(Mandatory=$True)]
    [string] $DiskName
  )

  $diskSource = "\\vmware-host\Shared Folders\viresh001\azure-war-pig\$DiskName.vhd"
  $diskDestination = "https://$StorageAccountName.blob.core.windows.net/upload/$DiskName.vhd"
  Add-AzureVhd -LocalFilePath $diskSource -Destination $diskDestination -OverWrite

  #associate vhd files with diskName
  if(!((Get-AzureDisk) | where { $_.DiskName -eq $DiskName} ))  {
    Add-AzureDisk -DiskName $DiskName -MediaLocation $diskDestination
  }

  $vm = Get-AzureVM -ServiceName $CloudServiceName -Name $VMName

  if(!(($vm | Get-AzureDataDisk) | where  { $_.DiskName -eq $DiskName }))  {
    $vm | Add-AzureDataDisk -Import -Diskname $DiskName -LUN 1 | Update-AzureVM
  }
}

Function Quick-CreateVM()
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $CloudServiceName, 

    [Parameter(Mandatory=$True)]
    [string] $VMName,

    [Parameter(Mandatory=$True)]
    [string] $ImageName,

    [Parameter(Mandatory=$True)]
    [string] $InstanceSize,

    [Parameter(Mandatory=$True)]
    [string] $AdminUsername,

    [Parameter(Mandatory=$True)]
    [string] $Password
  )
  Azure\Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccountName $StorageAccountName

  New-AzureQuickVM -Windows -ServiceName $CloudServiceName -Name $VMName -ImageName $ImageName -InstanceSize $InstanceSize -AdminUsername $AdminUser -Password $Password -WaitForBoot
}

Function Remove-CloudService()
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $CloudServiceName
  )
  $csList = Get-AzureService | where{$_.ServiceName -match $CloudServiceName} -ErrorAction Stop
  foreach($cloudService in $csList)  {
    $cloudService | Remove-AzureService -DeleteAll -Force -ErrorAction Stop
  }
}

Function Remove-StorageAccount()
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $StorageAccountName
  )
  Remove-StorageAccount -StorageAccountName $StorageAccountName
}

Function Install-WinRMCertificateForVM()
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $CloudServiceName, 

    [Parameter(Mandatory=$True)]
    [string] $VMName
  )
  if((IsAdmin) -eq $false)  {
    Write-Error "Must run PowerShell elevated to install WinRM certificates."
	return
  }

  $winRMCert = (Get-AzureVM -ServiceName $CloudServiceName -Name $VMName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
  $azureX509Cert = Get-AzureCertificate -ServiceName $CloudServiceName -Thumbprint $winRMCert -ThumbprintAlgorithm sha1

  $certTempFile = [IO.Path]::GetTempFileName()
  $azureX509cert.Data | Out-File $certTempFile

  #target The Cert That Needs To Be Imported
  $CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certTempFile

  $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
  $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
  $store.Add($CertToImport)
  $store.Close()

  Remove-Item $certTempFile

}

Function Execute-RemotePowershell()
{
  param(
    [Parameter(Mandatory=$True)]
    [string] $CloudServiceName, 

    [Parameter(Mandatory=$True)]
    [string] $VMName,

    [Parameter(Mandatory=$True)]
    [string] $AdminUser,

    [Parameter(Mandatory=$True)]
    [string] $Password
  )

  $uri = Get-AzureWinRMUri -ServiceName $CloudServiceName -Name $VMName

  #create credential object to log-in automatically
  $secureString = New-Object -TypeName System.Security.SecureString
  $Password.ToCharArray() | ForEach-Object {$secureString.AppendChar($_)}
  $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $AdminUser, $secureString

  #Enter-PSSession -ConnectionUri $uri -Credential $cred
  Invoke-Command -ConnectionUri $uri -Credential $cred -ScriptBlock {Install-WindowsFeature -Name "Web-Server" -IncludeAllSubFeature -IncludeManagementTools}
}

Set-AzureSubscription -SubscriptionName $subscriptionName
Create-StorageAccount -SubscriptionName $subscriptionName -StorageAccountName $storageAccountName -Location $location
Create-CloudService -CloudServiceName $cloudServiceName -Location $location
Quick-CreateVM -CloudServiceName $cloudServiceName -VMName $vmName -ImageName $imageName -InstanceSize $vmSize -AdminUsername $adminUser -Password $password
Add-Disk -CloudServiceName $cloudServiceName -VMName $vmName -DiskName $diskName -StorageAccountName $storageAccountName

Install-WinRMCertificateForVM -CloudServiceName $cloudServiceName -VMName $vmName

Execute-RemotePowershell -CloudServiceName $cloudServiceName -VMName $vmName -AdminUser $adminUser -Password $password





