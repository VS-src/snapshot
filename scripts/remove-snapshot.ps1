[CmdLetBinding()]
Param(
    # vCenter server name
    [Parameter(Mandatory)]
    [string[]]$Server,

    [Parameter(Mandatory)]
    [pscredential]$Credential,
    
    [Parameter(Mandatory)]
    [ValidateSet('lab','prod')]
    [string]$Environment
)



function Import-Config
{
[cmdLetBinding()]
Param(
    [Parameter(Mandatory)]
    [ValidateSet('lab','prod')]
    [string]$Environment
)

    $repoPath = Split-Path -Path $PSScriptRoot -Parent
    $configPath  = Join-Path $repoPath "envs\$Environment\config.json"    
    try 
    {
        $config = Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop    
    }
    catch 
    {
        throw "Failed to load configuration. $_"
    }
    $config
}


$config = Import-Config -Environment $Environment
$cutoffDate = (Get-Date).AddDays(-$config.SnapshotAgeDays)
$vmExclusionPatterns = @($config.ExcludeVmPatterns)
$snapshotExclusionPatterns = @($config.ExcludeSnapshotPatterns)
$excluded = @()
$removed = @()
$failed = @()




foreach ($vcenter in $Server) {
    $vcConnection = $null
    $allSnapshots = @()
    try {
        $vcConnection = Connect-VIServer -Server $vcenter -Credential $Credential -ErrorAction Stop
        $allSnapshots = Get-VM -Server $vcConnection | Get-Snapshot | Where-Object {$_.Created -lt $cutoffDate}
    }
    catch {
        Write-Output "Error while processing vcenter. $_"
        continue
    }

    foreach ($snapshot in $allSnapshots){

        if ($vmExclusionPatterns | Where-Object { $snapshot.VM.Name -like $_}) {
            $excluded += [PSCustomObject]@{
                VM = $snapshot.VM.Name
                Snapshot = $snapshot.Name
                Created = $snapshot.Created
                SizeGB = $snapshot.SizeGB -as [int]
                Status = 'VMnameExcluded'
            }
            continue 
        }

        if ($snapshotExclusionPatterns | Where-Object {$snapshot.Name -like $_}) {
            $excluded += [PSCustomObject]@{
                VM = $snapshot.VM.Name
                Snapshot = $snapshot.Name
                Created = $snapshot.Created
                SizeGB = $snapshot.SizeGB -as [int]
                Status = 'SnapshotNameExcluded'
            }
            continue
        }

        try {
            #$snapshot | Remove-Snapshot -WhatIf
            $removed += [PSCustomObject]@{
                VM = $snapshot.VM.Name
                Snapshot = $snapshot.Name
                Created = $snapshot.Created
                SizeGB = $snapshot.SizeGB -as [int]
                Status = 'Removed'
           }

        }
        catch {
            Write-output "$($snapshot.name) - failed to remove)"
            $failed += [PSCustomObject]@{
                VM = $snapshot.VM.Name
                Snapshot = $snapshot.Name
                Created = $snapshot.Created
                SizeGB = $snapshot.SizeGB -as [int]
                Status = 'Failed'
            }
        }
    }
    
    if ($vcConnection) {
        Disconnect-VIServer -Server $vcConnection -Confirm:$false |Out-Null
    }

}


if ($removed) {
    Write-Output "Removed:"
    $removed 
}

if ($excluded) {
    Write-Output "Skipped:"
    $excluded
}

if ($failed) {
    Write-Output "Failed"
    $failed
}


    