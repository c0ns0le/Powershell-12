Function Get-SQLServerDBInfo {
    <#
    .SYNOPSIS
    Returns database and log information from a sql server.
    .DESCRIPTION
    Returns database and log information from a sql server. Useful for monitoring.
    .EXAMPLE
    Get-SQLInstance | %{Get-SQLServerDBInfo $_.FullName}
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true, HelpMessage="Server(s) to query.")]
        [string[]]$ComputerName        
    )
    
    begin {
        $Servers = @()
        ## Load the .NET assembly.
        if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")) {
            $AssemblyLoaded = $true
        }
        else {
            $AssemblyLoaded = $false
        }
    }
    
    process {
        $Servers += $ComputerName
    }
    end {
        if ($AssemblyLoaded) {
            foreach ($Server in $Servers) {
                try {
                    $srv = New-Object('Microsoft.SqlServer.Management.Smo.Server') $Server
                    foreach ($db in $srv.Databases) {
                        $dbname = $db.Name
                        $logInfo = $db.LogFiles | Select Name, FileName, Size, UsedSpace, MaxSize, Growth, GrowthType
                        $dbprops = @{}
                        $dbprops.Server = $Server
                        $dbprops.Database = $db.Name
                        $dbprops.RecoveryModel = $db.RecoveryModel
                        $dbprops.LastBackupDate = $db.LastBackupDate
                        $dbprops.LastLogBackupDate = $db.LastLogBackupDate
                        $dbprops.LogName = $logInfo.Name
                        $dbprops.LogFile = $logInfo.FileName
                        $dbprops.LogSize = $logInfo.Size
                        $dbprops.LogUsedSpace = $logInfo.UsedSpace
                        $dbprops.LogMaxSize = if ($logInfo.MaxSize -eq '-1'){'Unlimited'} else {$logInfo.MaxSize}
                        $dbprops.LogGrowth = $logInfo.Growth
                        $dbprops.LogGrowthType = $logInfo.GrowthType
                        try {
                            $fileGroups = $db.FileGroups
                            foreach ($fg in $fileGroups) {
                                if ($fg) {
                                    $mdfInfo = $fg.Files | Select Name, FileName, size, UsedSpace
                                    $dbprops.FileGroup = $fg.Name
                                    $dbprops.DBName = $mdfInfo.Name
                                    $dbprops.DBFile = $mdfInfo.FileName
                                    $dbprops.DBSize = $mdfInfo.size
                                    $dbprops.DBUsedSpace = $mdfInfo.UsedSpace 
                                }
                            }
                        }
                        catch {
                            Write-Warning -Message ('SQL DB Access Issue on Server - {0}, Database - {1}' -f $Server,$db.Name)
                            $dbprops.FileGroup = ''
                            $dbprops.DBName = ''
                            $dbprops.DBFile = ''
                            $dbprops.DBSize = ''
                            $dbprops.DBUsedSpace = ''
                        }
                        New-Object psobject -Property $dbprops
                    }
                }
                catch
                {
                    Write-Warning -Message ('Get-SQLServerDBInfo: Issue - {0}' -f $_.Exception.Message)
                }
            }
        }
    }
}