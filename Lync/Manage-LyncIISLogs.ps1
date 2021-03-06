<# 
.SYNOPSIS
Report upon and optionally delete old Lync IIS logs.
.DESCRIPTION
Report upon and optionally delete old Lync IIS logs.
.PARAMETER CreateScheduledTask
Use the current parameters and create a scheduled task from the current script. This defaults to the DeleteOldLogs scenario
and only passes the DaysToKeep and ServerFilter parameters.
.PARAMETER DaysToKeep
The number of days of log files to report upon or keep when deleting.
.PARAMETER FileTypes
If you want to target specific types of files send an array of file types (ie. '*.log','*.blg','*.bak'). Use '*' with
DaysToKeep at 0 in order to force the reporting to use psremoting and return only overall folder sizes as quickly as possible.
.PARAMETER Scenario
Choose one of 4 precreated scenarios:

RetrieveValidFolders – Gather a list of valid logging and temp folders. Does not calculate sizes.
ReportOldLogSize - Gather a list of valid logging and temp folders and also enumerate their total 
                   size as well as the size of all the old logs that exist before the specified number of days. 
                   This includes message tracking logs.
DeleteOldLogs – Attempt to delete all logs which are older than the number of days specified. This does NOT include 
                message tracking logs.
DeleteOldLogsTestRun – Same as DeleteOldLogs but without actually deleting anything (adds –WhatIf to all Remove-Item 
                       commands). This does NOT include message tracking logs.

.EXAMPLE
$oldlogs = .\Manage-LyncIISLogs.ps1 -DaysToKeep 14 -Scenario:ReportOldLogSize -Verbose
$oldlogs | ft -auto

Description
-----------
Get a size report for all servers of logs that are older than 14 days on all servers.

.EXAMPLE
$logdirsize = .\Manage-LyncIISLogs.ps1 -DaysToKeep 0 -FileTypes '*' -Scenario:ReportOldLogSize -Verbose
$oldlogs | ft -auto

Description
-----------
Get a size report for all servers of just the directories containing the logs. Using DaysToKeep of zero and FileTypes of
'*' ensures that remoting is used for all calculations thus speeding up results.

.EXAMPLE
$Folders = .\Manage-LyncIISLogs.ps1 -Scenario:RetrieveValidFolders -DaysToKeep 14 -Verbose
$Folders | select Server,Path | ft -auto

Description
-----------
Get a general report of all the lync servers and log paths.

.EXAMPLE
.\Manage-LyncIISLogs.ps1 -Scenario:DeleteOldLogsTestRun -DaysToKeep 14 -Verbose

Description
-----------
Perform a test run of removal of all .log and .blg files over 14 days old in all directories found on all lync 2010/2013 servers.

.EXAMPLE
.\Manage-LyncIISLogs.ps1 -Scenario:DeleteOldLogs -DaysToKeep 14 -Verbose

Description
-----------
Remove all .log and .blg files over 14 days old in all directories found on all lync 2010/2013 servers.

.EXAMPLE
$logdirsize = .\Manage-LyncIISLogs.ps1 -DaysToKeep 0 -FileTypes '*' -Scenario:ReportOldLogSize -ServerFilter 'EXCH2' -Verbose
.\Manage-LyncIISLogs.ps1 -Scenario:DeleteOldLogs -DaysToKeep 14 -ServerFilter 'EXCH2' -Verbose -FileTypes '*.log','*.blg','*.bak'
$newlogdirsize = .\Manage-LyncIISLogs.ps1 -DaysToKeep 0 -FileTypes '*' -Scenario:ReportOldLogSize -ServerFilter 'EXCH2' -Verbose
$logdirsize | %{ $logdir = $_; $newlogdir = $newlogdirsize | where {$_.Description -eq $logdir.description}; New-Object psobject -Property @{'Log' = $logdir.Description;'OldSize' = $logdir.TotalSize;'NewSize' = $newlogdir.Totalsize}}|Select log,Oldsize,Newsize | ft -auto

Description
-----------
For the EXCH2 server perform the following actions:
1. Get a list of directories which can be cleaned, and force the function to only use psremoting to get the total directory size
2. Remove all .log,.blg, and .bak files over 14 days old in all applicable directories found on the server.
3. Get an updated directory size listing using psremoting
4. Display all log types with their prior and new directory size.

.EXAMPLE
.\Manage-LyncIISLogs.ps1 -Scenario:DeleteOldLogs -DaysToKeep 5 -CreateScheduledTask

Description
-----------
Creates a scheduled task on the current server to run this script every night at 3am and delete logs older than 5 days on all Lync servers.

.NOTES
Author: Zachary Loeber
Version History:
    1.0 - 12/10/2014
        - Initial Release

.LINK
www.the-little-things.net

.LINK
https://github.com/zloeber/Powershell/
#> 

param(
    [parameter(Mandatory=$true, HelpMessage='Number of days for old log files.')]
    [int]$DaysToKeep = 14,
    [Parameter(HelpMessage='Default file types to clean up or report upon. Usually leave this alone.')]
    [string[]]$FileTypes = @('*.log','*.blg'),
    [Parameter(Mandatory=$true, HelpMessage='Scenario to run.')]
    [ValidateSet('RetrieveValidFolders',
                 'ReportOldLogSize',
                 'DeleteOldLogs',
                 'DeleteOldLogsTestRun')]
    [string]$Scenario,
    [Parameter(HelpMessage='Alternate psremoting port to use.')]
    [int]$port,
    [Parameter(HelpMessage='Create a scheduled task for logfile removal with the current parameters.')]
    [switch]$CreateScheduledTask
)

function Get-ScriptName { 
    if($hostinvocation -ne $null)
    {
        $hostinvocation.MyCommand.path
    }
    else
    {
        $script:MyInvocation.MyCommand.Path
    }
}

function New-ScheduledPowershellTask {
    <#
    .SYNOPSIS

    .DESCRIPTION

    .PARAMETER 

    .PARAMETER 

    .LINK
    http://www.the-little-things.net
    .LINK
    https://github.com/zloeber/Powershell/
    .NOTES
    Last edit   :   
    Version     :   
    Author      :   Zachary Loeber

    .EXAMPLE


    Description
    -----------
    TBD
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Position=0, HelpMessage='Task Name. If not set a random GUID will be used for the task name.')]
        [string]$TaskName,
        [Parameter(Position=1, HelpMessage='Task Description.')]
        [string]$TaskDescription,
        [Parameter(Position=2, HelpMessage='Task Script.')]
        [string]$TaskScript,
        [Parameter(Position=3, HelpMessage='Task Script Arguments.')]
        [string]$TaskScriptArgs,
        [Parameter(Position=4, HelpMessage='Task Start Time (defaults to 3AM tonight).')]
        [datetime]$TaskStartTime = "$(Get-Date "$(((Get-Date).AddDays(1)).ToShortDateString()) 3:00 AM")"
    )
    begin {
        # The Task Action command
        $TaskCommand = "c:\windows\system32\WindowsPowerShell\v1.0\powershell.exe"

        # The Task Action command argument
        $TaskArg = "-WindowStyle Hidden -NonInteractive -Executionpolicy unrestricted -command `"& `'$TaskScript`' $TaskScriptArgs`""
 
    }
    process {}
    end {
        try {
            # attach the Task Scheduler com object
            $service = new-object -ComObject("Schedule.Service")
            # connect to the local machine. 
            # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381833(v=vs.85).aspx
            $service.Connect()
            $rootFolder = $service.GetFolder("\")
             
            $TaskDefinition = $service.NewTask(0) 
            $TaskDefinition.RegistrationInfo.Description = "$TaskDescription"
            $TaskDefinition.Settings.Enabled = $true
            $TaskDefinition.Settings.AllowDemandStart = $true
             
            $triggers = $TaskDefinition.Triggers
            #http://msdn.microsoft.com/en-us/library/windows/desktop/aa383915(v=vs.85).aspx
            $trigger = $triggers.Create(2) # Creates a daily trigger
            $trigger.StartBoundary = $TaskStartTime.ToString("yyyy-MM-dd'T'HH:mm:ss")
            $trigger.Enabled = $true
             
            # http://msdn.microsoft.com/en-us/library/windows/desktop/aa381841(v=vs.85).aspx
            $Action = $TaskDefinition.Actions.Create(0)
            $action.Path = "$TaskCommand"
            $action.Arguments = "$TaskArg"
             
            #http://msdn.microsoft.com/en-us/library/windows/desktop/aa381365(v=vs.85).aspx
            $rootFolder.RegisterTaskDefinition("$TaskName",$TaskDefinition,6,"System",$null,5) | Out-Null
        }
        catch {
            throw
        }
    }
}

function Get-FolderSize {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage='Directory path')]
        [string]$path,
        [Parameter(HelpMessage='Only include data older than this number of days in calculation. Ignored if set to zero.')]
        [int]$days = 0,
        [Parameter(HelpMessage='Only include files matching this criteria.')]
        [string[]]$criteria = '*',
        [string]$ComputerName,
        [switch]$UseRemoting,
        [int]$port,
        [System.Management.Automation.Runspaces.PSSession]$Session = $null

    )
    $InvokeSplat = @{}

    $LocalPath = $false
    if ($path -like '*:*') {
        $LocalPath = $true
    }
    elseif ($path -like '\\*') {
        if ($path -match '\\\\(.*?)\\') {
            $ComputerName = $Matches[1]
        }
        else {
            throw 'Get-FolderSize: Invalid Path!'
        }

        $IPAddresses = [net.dns]::GetHostAddresses($env:COMPUTERNAME) | Select-Object -ExpandProperty IpAddressToString
        $HostNames = $IPAddresses | ForEach-Object {
            try {
                [net.dns]::GetHostByAddress($_)
            } 
            catch {}
        } | Select-Object -ExpandProperty HostName -Unique
        $LocalHost = @('', '.', 'localhost', $env:COMPUTERNAME, '::1', '127.0.0.1') + $IPAddresses + $HostNames
        if ($LocalHost -contains $ComputerName) {
            $LocalPath = $true
        }
    }
    
    if (Test-Path $path) {
        if (($LocalPath -or $UseRemoting) -and (($days -eq 0) -and ($criteria -eq '*'))) {   # using fso (faster)
            # convert to local pathname first
            $path = $path -replace '\$',':' -replace '(^\\\\.*?\\)',''
            if ($UseRemoting) {
                if ($Session -ne $null) {
                    $InvokeSplat.Session = $Session
                }
                else {
                    $InvokeSplat.ComputerName = $ComputerName
                    if ($port -ne 0) {
                        $InvokeSplat.Port = $port
                    }
                }
                Write-Verbose "$($MyInvocation.MyCommand): Using remoting with FileSystemObject on $ComputerName to enumerate $path..."
                $RemoteCMDString = "`$objFSO = New-Object -com  Scripting.FileSystemObject; `$objFSO.GetFolder(`'$path`').Size"
                $RemoteCMD = [scriptblock]::Create($RemoteCMDString)
                return $(Invoke-Command @InvokeSplat -ScriptBlock $RemoteCMD)
            }
            else {
                Write-Verbose "Get-FolderSize: Using FileSystemObject on localhost to enumerate $path..."
                $objFSO = New-Object -com  Scripting.FileSystemObject
                return $objFSO.GetFolder($path).Size
            }
        }
        else {
            # pure powershell (slower)
            Write-Verbose "Get-FolderSize: Using powershell to enumerate $path..."
            $LastWrite = (Get-Date).AddDays(-$days)
            $colItems = (Get-ChildItem -Recurse $path -Include $criteria -ErrorAction:SilentlyContinue | 
                            Where {$_.LastWriteTime -le "$LastWrite"} | 
                                Measure-Object -property length -sum)
            return $colItems.sum
        }
    }
    else {
        Write-Warning "$($MyInvocation.MyCommand): Invalid Path!"
    }
}

filter ConvertTo-KMG {
    $bytecount = $_
    switch ([math]::truncate([math]::log($bytecount,1024))) {
          0 {"$bytecount Bytes"}
          1 {"{0:n2} KB" -f ($bytecount / 1kb)}
          2 {"{0:n2} MB" -f ($bytecount / 1mb)}
          3 {"{0:n2} GB" -f ($bytecount / 1gb)}
          4 {"{0:n2} TB" -f ($bytecount / 1tb)}
    default {"{0:n2} KB" -f ($bytecount / 1kb)}
    }
}
            
function Delete-LogFiles {
    [CmdletBinding()]
    param (
        [Parameter(HelpMessage='Server to clean.')]
        [string]$server = $Env:COMPUTERNAME,
        [Parameter(Mandatory=$true, HelpMessage='Path to clean.')]
        [string]$path,
        [Parameter(HelpMessage='Days to keep.')]
        [int]$days = 14,
        [Parameter(Mandatory=$true, HelpMessage='Path to clean.')]
        [string[]]$FileTypes = @('*.log','*.blg'),
        [Parameter(HelpMessage='Delete empty directories as well.')]
        [switch]$DeleteDirectories,
        [Parameter(HelpMessage='Perform a test run, do not delete anything.')]
        [switch]$testrun,
        [Parameter(HelpMessage='Instead of using psremoting use admin shares to delete files.')]
        [switch]$UsePSRemoting
    )
    if (-not $UsePSRemoting) {
        # Build full UNC path
        $path = $path -replace ':','$'
        $TargetServerFolder = "\\" + $server + "\" + $path
    }
    else {
        $TargetServerFolder = $path
    }
    Write-Verbose "$($MyInvocation.MyCommand): Attempting to clean logs located in $TargetServerFolder"
    # Only try to delete files, if folder exists
    if (Test-Path $TargetServerFolder) {
        $LastWrite = (Get-Date).AddDays(-$days)

        # Select files to delete
        $Files = Get-ChildItem $TargetServerFolder -File -Include $FileTypes -Recurse | Where {$_.LastWriteTime -le "$LastWrite"}

        $FileCount = 0
        $DirectoryCount = 0
        $Whatif = @{}
        
        if ($testrun) {
            $Whatif.whatif = $true
        }
        # Delete the files
        $Files | Foreach {
            try {
                Remove-Item $_ -Force -Confirm:$false -ErrorAction:Stop @Whatif
                $fileCount++
            }
            catch {}
        }
        Write-Verbose "$($MyInvocation.MyCommand): $fileCount of $($Files.Count) deleted in $TargetServerFolder"
        
        # Delete empty directories (BE CAREFULL WITH THIS!)
        if ($DeleteDirectories) {
            $Directories = Get-ChildItem $TargetServerFolder -Directory -Recurse | Where {$_.LastWriteTime -le "$LastWrite"}
            foreach($Directory in $Directories) {
                if ((Test-Path $Directory.Fullname)) {
                    if ((get-childitem $Directory.Fullname -Recurse -File).Count -eq 0) {
                        Remove-Item $Directory.Fullname -Confirm:$false -ErrorAction:Stop -Force @Whatif
                        $DirectoryCount++
                    }
                }
            }
            Write-Verbose "$($MyInvocation.MyCommand): $DirectoryCount of $($Directories.Count) deleted in $TargetServerFolder"
        }
    }
    else {
        # oops, folder does not exist or is not accessible
        Write-Warning "$($MyInvocation.MyCommand): The folder $TargetServerFolder doesn't exist or is not accessible."
    }
}

function Get-LyncServers {
    # Short function to pull out some of the general Lync servers in a deployment
    $DatabaseServers = @()
    $FrontEndServers = @()
    $EdgeServers = @()
    $PChatServers = @()
    $Pools = get-cspool 
    Foreach ($Pool in $Pools) {
        switch -wildcard ($Pool.Services) {
            '*Database:*' {
                $DatabaseServers += $Pool.Computers
            }
            'EdgeServer:*' {
                $EdgeServers += $Pool.Computers
            }
            'WitnessStore:*' {
                $DatabaseServers += $Pool.Computers
            }
            'Registrar:*' {
                $FrontEndServers += $Pool.Computers
            }
            'PersistentChatServer:*' {
                $PChatServers += $Pool.Computers
            }
        }
    }
    $PChatServers | Select -Unique | %{New-Object psobject -Property @{'Type' = 'PersistentChat'; 'Server' = $_}}
    $FrontEndServers | Select -Unique | %{New-Object psobject -Property @{'Type' = 'FrontEnd'; 'Server' = $_}}
    $EdgeServers | Select -Unique | %{New-Object psobject -Property @{'Type' = 'Edge'; 'Server' = $_}}
    $DatabaseServers | Select -Unique | %{New-Object psobject -Property @{'Type' = 'Database'; 'Server' = $_}}
}

function Get-OldIISLogFileInfo {
    [CmdletBinding()]
    param(
        [parameter(HelpMessage='Number of days for log files retention. Used to determine overall size of files which can be removed.')]
        [int]$DaysToKeep = 14,
        [Parameter(HelpMessage='Default file types to clean up or report upon. Usually leave this alone.')]
        [string[]]$FileTypes = @('*.log','*.blg'),
        [Parameter(HelpMessage='Speeds up operations if just looking for valid paths to clean up.')]
        [switch]$SkipSizeCalculation,
        [Parameter(HelpMessage='One or more servers.')]
        [string[]]$ComputerName = $env:COMPUTERNAME,
        [int]$port
    )
    begin {
        $ComputerNames = @()
        $IISPaths = @()
        $Verbosity=@{}
        if ($PSBoundParameters['Verbose'] -eq $true) {
            $Verbosity.Verbose = $true
        }

        # scripts for remote session execution
        $IisLogPathScript = [scriptblock]::Create('Import-Module WebAdministration; (Get-WebConfigurationProperty "system.applicationHost/sites/siteDefaults" -Name logFile).directory | Foreach {$_ -replace "%SystemDrive%", $env:SystemDrive}')

        function Get-FolderInformation {
          [CmdletBinding()]
            param (
                [string]$Server,
                [string]$Path,
                [string]$Description,
                [int]$Days = 14,
                [string[]]$FileTypes = @('*.log','*.blg'),
                [switch]$SkipSizeCalculation,
                [System.Management.Automation.Runspaces.PSSession]$Session
            )
            $Verbosity=@{}
            if ($PSBoundParameters['Verbose'] -eq $true) {
                $Verbosity.Verbose = $true
            }
            $UNC = '\\' + $Server + '\' + ($Path -replace ':','$')
            if (Test-Path $UNC) {
                $TotalSize = 0
                $OldSize = 0
                if (-not $SkipSizeCalculation) {
                    Write-Verbose "$($MyInvocation.MyCommand): Calculating Disk Utilization: $Description - Total Files Size..."
                    $TotalSize = Get-FolderSize -Path $UNC -UseRemoting @Verbosity
                    Write-Verbose "$($MyInvocation.MyCommand): Calculating Disk Utilization: $Description - Old Files Size..."
                    $OldSize = Get-FolderSize -Path $UNC -Days $Days -Criteria $FileTypes -UseRemoting @Verbosity
                }
                New-Object PSObject -Property @{
                    'Server' = $Server
                    'Path' = $Path
                    'UNC' = $UNC
                    'Description' = $Description
                    'TotalSize' = $TotalSize
                    'OldDataSize' = $OldSize
                }
            }
        }
    }
    process {
        $ComputerNames += $ComputerName
    }
    end {
        foreach ($Computer in $ComputerNames) {
            Write-Verbose "$($MyInvocation.MyCommand): Proccessing server $Computer"
            try {
                $pssessionsplat = @{}
                if ($port -ne 0) {
                    $pssessionsplat.port = $port
                }
                $RemoteSession = New-PSSession -ComputerName $Computer @pssessionsplat
                $RemoteSessionConnected = $true
            }
            catch {
                $RemoteSessionConnected = $false
                Write-Warning "$($MyInvocation.MyCommand): Unable to establish psremoting session with $Computer"
            }
            if ($RemoteSessionConnected) {
                $GetFolderInfoSplat = @{
                        'Server' = $Computer
                        'Path' = ''
                        'Days' = $DaysToKeep
                        'Description' = ''
                        'FileTypes' = $Filetypes
                        'SkipSizeCalculation' = $SkipSizeCalculation
                        'Session' = $RemoteSession
                }
                
                Write-Verbose "$($MyInvocation.MyCommand): Processing Server - $Computer"
                
                try {
                    Write-Verbose "Get-OldIISLogFileInfo: Remotely determining IIS log file location...."
                    $IisLogPath = Invoke-Command -ScriptBlock $IisLogPathScript -Session $RemoteSession
                }
                catch {
                    $IisLogPath = ''
                    Write-Verbose "Get-OldIISLogFileInfo: IIS log path not found on $($Server). Please ensure that WinRM is enabled."
                }
                if ($IisLogPath -ne '') {
                    $GetFolderInfoSplat.Path = $IisLogPath
                    $GetFolderInfoSplat.Description = 'IIS Logs'
                    $FolderResults = Get-FolderInformation @GetFolderInfoSplat @Verbosity
                    if ($FolderResults -ne $null) {$IISPaths += $FolderResults}
                }
                Remove-PSSession $RemoteSession
            }
        }
        return $IISPaths
    }
}

function Delete-OldIISLogs {
    [CmdletBinding()]
    param(
        [parameter(Position=0,HelpMessage='Number of days for log files retention. Used to determine overall size of files which can be removed.')]
        [int]$DaysToKeep = 14,
        [Parameter(HelpMessage='Select one or more specific Servers')]
        [string[]]$ComputerName = '*',
        [string[]]$FileTypes = @('*.log','*.blg'),
        [switch]$testrun
    )
    $Testrunsplat = @{}
    if ($testrun) {
        $Testrunsplat.testrun = $true
    }
    $Verbositysplat = @{}
    if ($PSBoundParameters['Verbose'] -eq $true) {
        $Verbositysplat.Verbose = $true
    }
    
    $oldlogs = @(Get-OldIISLogFileInfo -SkipSizeCalculation -ComputerName $ComputerName @Verbositysplat)
    $oldlogs | Foreach {
        Delete-LogFiles -Server $_.Server -path $_.Path -days $DaysToKeep -FileTypes $FileTypes @testrunsplat @Verbositysplat
    }
}

Import-Module Lync -ErrorAction:SilentlyContinue -Verbose:$false
if ((get-module lync) -eq $null)
{
    Write-Warning "This script must be run on a lync server. Exiting!"
    Break
}

$LyncServers = @((Get-LyncServers | Where {$_.Type -eq 'FrontEnd'}).Server)

if ($CreateScheduledTask) {
    $ScriptName = Get-ScriptName
    $TaskScriptArgs = "-DaysToKeep:$($DaysToKeep) -Scenario:DeleteOldLogs"
    New-ScheduledPowershellTask -TaskName 'Clean Lync IIS Logs' -TaskDescription 'Clean Old IIS logs' -TaskScript $ScriptName -TaskScriptArgs $TaskScriptArgs
    Write-Output "Assuming there were no errors, the scheduled task has been created on the localhost as `'Clean Lync IIS Logs`'"
    Write-Output "You still need to go into scheduled tasks and modify the task to run as an appropriate service account!"
    break
}

# ** Main **
# Define custom function splats for later on
$Verbositysplat = @{}
$CustomPortSplat = @{}
if ($PSBoundParameters['Verbose'] -eq $true) {
    $Verbositysplat.Verbose = $true
}
if ($port -ne 0) {
    $CustomPortSplat.Port = $port
}

switch ($Scenario) {
    'RetrieveValidFolders' {
        Get-OldIISLogFileInfo -SkipSizeCalculation -ComputerName $LyncServers @CustomPortSplat @Verbositysplat
    }

    'ReportOldLogSize' {
        # Generate a report of total directory size and how much the 'old' log data consumes
        Get-OldIISLogFileInfo -DaysToKeep $DaysToKeep -ComputerName $LyncServers @CustomPortSplat -FileTypes $FileTypes @Verbositysplat | 
            Select-Object Server,Description,Path,@{n='UsedSize';e={$_.OldDataSize | Convertto-KMG}},@{n='TotalSize';e={$_.TotalSize | Convertto-KMG}}
    }

    'DeleteOldLogs' {
        Delete-OldIISLogs -DaysToKeep $DaysToKeep -ComputerName $LyncServers -FileType $FileTypes @Verbositysplat
    }

    'DeleteOldLogsTestRun' {
        Delete-OldIISLogs -DaysToKeep $DaysToKeep -ComputerName $LyncServers -FileType $FileTypes -testrun @Verbositysplat
    }
}