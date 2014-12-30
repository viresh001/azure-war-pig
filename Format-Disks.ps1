
param (
  $lables
)

$labelsArguments = $labels.Split(";")

$diskList = Get-Disk | where { $_.PartitionStyle -eq "raw" } | sort number

$letters = 70..89 | foreach {([char] $_)}

$count = 0

foreach ($disk in $diskList)  {
  $driveLetter = $letters[$count].ToString()

  $disk | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -UseMaximumSize -DriveLetter $driveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel $labelsArguments[$count] -Confirm:$false -Force
  $count++
}