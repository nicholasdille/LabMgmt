. "$PSScriptRoot\VMManagement.ps1"

$VMName = 'Test'
If (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    Remove-LabVM -Name $VMName
}

$BaseDiskName = Get-BaseDisk
Add-LabVM -Name $VMName -BaseDisk $BaseDiskName
Add-UnattendedSetup -Name $VMName -Path "$PSScriptRoot\unattend.xml"