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

foreach ($vcenter in $Server)
{
    $vcConnection  = Connect-VIServer -Server $vcenter -Credential $Credential -ErrorAction Stop
    $allVms = get-vm -Server $vcConnection
    $allSnapshots = $allVms | Get-Snapshot | Where-Object {$_.Created -lt $cutoffDate}
    $allSnapshots | Remove-Snapshot -WhatIf
    Disconnect-VIServer $vcConnection -Confirm:$false | Out-Null
}

    
