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


function Get-EligibleSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject[]]$Snapshot,

        [Parameter(Mandatory)]
        [datetime]$CutoffDate,

        [string[]]$VmExclusionPattern = @(),

        [string[]]$SnapshotExclusionPattern = @()
    )

    
    foreach ($item in $Snapshot) {
        $reason = $null

        foreach ($pattern in $VmExclusionPattern) {
            if ($item.VM.Name -like $pattern) {
                $reason = "VM matches exclusion pattern: $pattern"
                break
            }
        }

        if (-not $reason) {
            foreach ($pattern in $SnapshotExclusionPattern) {
                if ($item.Name -like $pattern) {
                    $reason = "Snapshot matches exclusion pattern: $pattern"
                    break
                }
            }
        }

        if (-not $reason -and $item.Created -ge $CutoffDate) {
            $reason = 'Snapshot is not old enough'
        }

        [PSCustomObject]@{
            Status   = if ($reason) { 'Skipped' } else { 'Eligible' }
            VM       = $item.VM
            Name     = $item.Name
            Created  = $item.Created
            Reason   = $reason
            Snapshot = $item
        }
    }
}

$config = Import-Config -Environment $Environment
$cutoffDate = (Get-Date).AddDays(-$config.SnapshotAgeDays)
$vmExclusionPattern = $config.ExcludeVmPatters
$snapshotExclusionPattern = $config.ExcludeSnapshotPatterns


foreach ($vcenter in $Server) {
    $vcConnection = Connect-VIServer -Server $vcenter -Credential $Credential -ErrorAction Stop

    $allSnapshots = Get-VM -Server $vcConnection | Get-Snapshot

    $results = @(
        $allSnapshots | Get-EligibleSnapshot -CutoffDate $cutoffDate -VmExclusionPattern $vmExclusionPattern -SnapshotExclusionPattern $snapshotExclusionPattern
    )

    $eligible = @($results | Where-Object Status -eq 'Eligible')
    $skipped  = @($results | Where-Object Status -eq 'Skipped')

    $eligible | Select-Object VM, Name, Created
    $skipped  | Select-Object VM, Name, Created, Reason

    if ($eligible.Count -gt 0) {
        $eligible.Snapshot | Remove-Snapshot -WhatIf
    }

    Disconnect-VIServer -Server $vcConnection -Confirm:$false |Out-Null
}
    