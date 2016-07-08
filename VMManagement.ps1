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
    #Add-LabVM
    #Merge
}

Function Add-LabVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseDisk
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Template = 'Default'
        ,
        [Parameter()]
        [switch]
        $NewBaseDisk
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
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
        If (-Not $NewVM) {
            throw ('Failed to create VM <{0}>' -f $Name)
        }
        
        $SetVMParams = @{
            Name           = $Name
            ProcessorCount = $VMTemplate.Cores
        }
        If ($ComputerName) {
            $SetVMParams.Add('ComputerName', $ComputerName)
        }
        Set-VM @SetVMParams

        $GetIntegrationParams = @{
            VMName = $Name
        }
        $SetIntegrationParams = @{}
        If ($ComputerName) {
            $GetIntegrationParams.Add('ComputerName', $ComputerName)
            $SetIntegrationParams.Add('ComputerName', $ComputerName)
        }
        Get-VMIntegrationService @GetIntegrationParams | Enable-VMIntegrationService @SetIntegrationParams

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

        $GetFirmwareParams = @{
            VMName = $Name
        }
        If ($ComputerName) {
            $GetFirmwareParams.Add('ComputerName', $ComputerName)
        }
        $BootDevice = Get-VMFirmware @GetFirmwareParams | Select-Object -ExpandProperty BootOrder
        $Vhd = $BootDevice | Where-Object {$_.BootType -ieq 'Drive'}
        $Net = $BootDevice | Where-Object {$_.BootType -ieq 'Network'}
        $SetFirmwareParams = @{
            VMName = $Name
            BootOrder = $Vhd, $Net
        }
        If ($ComputerName) {
            $SetFirmwareParams.Add('ComputerName', $ComputerName)
        }
        Set-VMFirmware -VMName $Name -BootOrder $Vhd,$Net
    }
}

Function Add-UnattendedSetup {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
     )

    Process {
        $GetDiskParams = @{
            VMName = $Name
        }
        $GetVhdParams = @{}
        If ($ComputerName) {
            $GetDiskParams.Add('ComputerName', $ComputerName)
            $GetVhdParams.Add('ComputerName', $ComputerName)
        }
        $VhdPath = Get-VMHardDiskDrive @GetDiskParams | Select-Object -ExpandProperty Path | Get-VHD @GetVhdParams | Where-Object {$_.VHDType -ieq 'Differencing'} | Select-Object -ExpandProperty Path
        
        #TODO: Remoting
        Mount-VHD -Path $VhdPath
        #TODO: Remoting
        $MountInfo = Get-VHD -Path $VhdPath
        #TODO: Remoting
        $SystemPartition = Get-Disk -Number $MountInfo.DiskNumber | Get-Partition | Where-Object {-Not $_.IsHidden}
        $VhdDrive = $SystemPartition.DriveLetter
        #TODO: Remoting
        Copy-Item -Path $Path -Destination "$($VhdDrive):\Windows\System32\Sysprep"
        #TODO: Remoting
        Dismount-VHD -Path $VhdPath
    }
}

Function Remove-LabVM {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
    )

    Process {
        If ((Get-VM -Name $Name).State -ieq 'Running') {
            Stop-VM -Name $Name -TurnOff -Force
        }
        
        #TODO: Remoting
        $VhdPath = Get-VMHardDiskDrive -VMName Test | Select-Object -ExpandProperty Path

        $RemoveVMParams = @{
            Name = $Name
        }
        If ($ComputerName) {
            $RemoveVMParams.Add('ComputerName', $ComputerName)
        }
        Remove-VM @RemoveVMParams -Force

        #TODO: Remoting
        If (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
            throw ('Failed to remove VM <{0}>' -f $Name)
        }

        #TODO: Remoting
        $VhdPath | Remove-Item
    }
}

Function New-VMDataDisk {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    Process {
        $DataDiskPath = '{0}\Data_{1}.vhdx' -f $Configuration.Storage.VHD, $Name
        #TODO: Remoting
        New-VHD -Path $DataDiskPath -SizeBytes 100GB -Dynamic | Out-Null

        #TODO: Partition and format
    }
}

Function Get-VMDataDisk {
    [CmdletBinding()]
    Param()

    Process {
        Get-ChildItem -Path $Configuration.Storage.VHD -Filter 'Data_*.vhdx' | Select-Object -ExpandProperty BaseName | ForEach-Object {
            If ($_ -imatch '^Data_(.+)$') {
                $Matches[1]
            }
        } | Where-Object {$_ -inotmatch '^(.+)@(.+)$'}
    }
}

Function Add-VMDataDisk {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DataDisk
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
    )

    Process {
        $NewVhdParams = @{
            Path       = '{0}\Data_{1}@{2}.vhdx' -f $Configuration.Storage.VHD, $DataDisk, $Name
            ParentPath = '{0}\Data_{1}.vhdx' -f $Configuration.Storage.VHD, $DataDisk
        }
        If ($ComputerName) {
            $NewVhdParams.Add('ComputerName', $ComputerName)    
        }
        $NewVhd = New-VHD @NewVhdParams

        If (-Not $NewVhd) {
            throw ('Failed to attach data disk <{0}>' -f $DataDisk)
        }

        $AddDiskParams = @{
            VMName = $Name
            Path   = $NewVhdParams.Path
        }
        If ($ComputerName) {
            $AddDiskParams.Add('ComputerName', $ComputerName)
        }
        Add-VMHardDiskDrive @AddDiskParams

        #TODO: Take online
    }
}

Function Remove-VMDataDisk {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
        ,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $DataDisk
        ,
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName
    )

    Process {
        #TODO: Take offline

        $DiskParams = @{
            VMName = $Name
        }
        If ($ComputerName) {
            $DiskParams.Add('ComputerName', $ComputerName)
        }
        $Vhd = Get-VMHardDiskDrive @DiskParams | Where-Object {$_.Path -imatch "\\Data_(.+)@$Name.vhdx$"}
        $VhdPath = $Vhd.Path

        Remove-VMHardDiskDrive -VMHardDiskDrive $Vhd

        #TODO Remoting
        Remove-Item -Path $VhdPath
    }
}

Function Start-VMDataDiskUpdate {
    #
}

Function Stop-VMDataDiskUpdate {
    #
}

Function Get-ISO {
    #
}

Function Add-ISO {
    #
}

Function Remove-ISO {
    #
}