. "$PSScriptRoot\VMManagement.ps1"

#New-VMDataDisk -Name 'DockerOfflineSetup'
$DataDisk = Get-VMDataDisk

$VMName = 'evalcont'
#Add-VMDataDisk -Name $VMName -DataDisk $DataDisk
Remove-VMDataDisk -Name $VMName -DataDisk $DataDisk