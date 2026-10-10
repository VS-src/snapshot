[CmdLetBinding()]
Param(
    # vCenter server name
    [Parameter(Mandatory)]
    [string[]]$Server,

    [Parameter(Mandatory)]
    [pscredential]$Credential
)




foreach ($vcenter in $Server)
{
    $vc_connection  = Connect-VIServer -Server $vcenter -Credential $Credential -ErrorAction Stop
    
    $all_vms = get-vm -Server $vc_connection
    $all_snapshots = $all_vms | Get-Snapshot

    $all_snapshots | Remove-Snapshot -WhatIf

    Disconnect-VIServer $vc_connection -Confirm:$false | Out-Null
}

    
