$Configuration = @{
    Library = @{
        VHD = 'D:\Library\VHD'
        ISO = 'D:\Library\ISO'
    }
    Storage = @{
        VM  = 'E:\VM_Storage'
        VHD = 'E:\VM_Storage'
    }
    Template = @(
        @{
            Name       = 'Default'
            Generation = 2
            Cores      = 2
            Memory     = 4GB
            Network    = 'Management'
        }
    )
}

Function Get-BaseDisk {
    [CmdletBinding()]
    Param(
        [Parameter()]
        [ValidateSet('1', '2')]
        [string]
        $Generation = 2
        ,
        [Parameter()]
        [ValidateSet('WS12R2', 'WS12R2U1NOV', 'WS2016TP4', 'WS2016TP5', 'Ubuntu1604')]
        [string]
        $OS = 'WS2016TP5'
    )

    Process {
        Get-ChildItem -Path $Configuration.Library.VHD | Select-Object -ExpandProperty BaseName | Where-Object {$_ -like "HyperV_Gen$($Generation)_$($OS)_*"} | Sort-Object -Descending | Select-Object -First 1
    }
}

Function Invoke-BaseDiskUpdate {
    #
}

Function Add-LabVM {
    [CmdletBinding()]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Template = 'Default'
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseDisk
        ,
        [Parameter()]
        [switch]
        $NewBaseDisk
    )

    Process {
        $VMTemplate = $Configuration.Template | Where-Object {$_.Name -ieq $Template}
        
        $NewVmParams = @{
            Name               = $Name
            Generation         = $VMTemplate.Generation
            MemoryStartupBytes = $VMTemplate.Memory
            SwitchName         = $VMTemplate.Network
        }
        If ($ComputerName) {
            $NewVmParams.Add('ComputerName', $ComputerName)
        }
        $NewVM = New-VM -NoVHD @NewVmParams
        
        $SetVMParams = @{
            Name           = $Name
            ProcessorCount = $VMTemplate.Cores
        }
        If ($ComputerName) {
            $SetVMParams.Add('ComputerName', $ComputerName)
        }
        Set-VM @SetVMParams

        Get-VMIntegrationService -VMName $Name | Enable-VMIntegrationService

        $BaseDiskPath = '{0}\{1}.vhdx' -f $Configuration.Library.VHD, $BaseDisk
        If (-Not (Test-Path -Path $BaseDiskPath)) {
            throw ('Base disk <{0}> not found' -f $BaseDisk)
        }
        $NewVHDParams = @{
            Path       = '{0}\{1}.vhdx' -f $Configuration.Storage.VHD, $Name
            ParentPath = $BaseDiskPath
        }
        If ($NewBaseDisk) {
            If ($BaseDiskPath -imatch '/(.+_)\d+.vhdx') {
                $NewBaseDiskName = "$($Matches[1])$(Get-Date -Format 'yyyyMMdd')"
            }
            $NewVHDParams.Path = '{0}\{1}.vhdx' -f $Configuration.Library.VHD, $NewBaseDiskName
        }
        If ($ComputerName) {
            $NewVHDParams.Add('ComputerName', $ComputerName)
        }
        #Write-Host ('New-VHD {0} {1}' -f ($NewVHDParams.Keys -join ','), ($NewVHDParams.Values -join ','))
        $NewVHD = New-VHD @NewVHDParams
        If (-Not $NewVHD) {
            throw ('Failed to create VHD from base disk <{0}>' -f $BaseDisk)
        }

        $AddDriveParams = @{
            VMName = $Name
            Path   = $NewVHD.Path
        }
        If ($ComputerName) {
            $AddDriveParams.Add('ComputerName', $ComputerName)
        }
        Add-VMHardDiskDrive @AddDriveParams
    }
}

Function Remove-LabVM {
    [CmdletBinding()]
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    Process {
        $VhdPath = Get-VMHardDiskDrive -VMName Test | Select-Object -ExpandProperty Path

        $RemoveVMParams = @{
            Name = $Name
        }
        If ($ComputerName) {
            $RemoveVMParams.Add('ComputerName', $ComputerName)
        }
        Remove-VM @RemoveVMParams -Force

        If (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
            throw ('Failed to remove VM <{0}>' -f $Name)
        }

        $VhdPath | Remove-Item
    }
}

#Remove-LabVM -Name 'Test'
$BaseDisk = Get-BaseDisk
Add-LabVM -Name 'Test' -BaseDisk $BaseDisk

Function Add-VMDataDisk {
    #
}

Function Remove-VMDataDisk {
    #
}

Function Update-VMDataDisk {
    #
}

Function Add-ISO {
    #
}

Function Remove-ISO {
    #
}