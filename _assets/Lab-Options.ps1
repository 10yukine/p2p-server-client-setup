function Get-LabDefaults {
    @{
        ServerIP='192.168.1.1'; ClientIP='192.168.1.2'; Prefix='24'; Gateway=''
        CreateShare=$true; OU=''; Users=''; LabPasswordRules=$false
        DHCP=$false; ScopeName='Lab DHCP'; RangeStart='192.168.1.100'; RangeEnd='192.168.1.150'
    }
}

function Convert-LabIPv4([string]$Address, [string]$Label) {
    $parts = $Address.Split('.')
    if ($parts.Count -ne 4 -or @($parts | Where-Object { $_ -notmatch '^(0|[1-9][0-9]{0,2})$' -or [int]$_ -gt 255 }).Count) {
        throw "$Label must be a dotted IPv4 address such as 192.168.1.10."
    }
    return [uint64]$parts[0] * 16777216 + [uint64]$parts[1] * 65536 + [uint64]$parts[2] * 256 + [uint64]$parts[3]
}

function Format-LabIPv4([uint64]$Address) {
    return ((24,16,8,0 | ForEach-Object { ($Address -shr $_) -band 255 }) -join '.')
}

function Read-LabOptions($Saved) {
    $lab = Get-LabDefaults
    foreach ($key in @($lab.Keys)) {
        if ($Saved -and $Saved.PSObject.Properties[$key]) { $lab[$key] = $Saved.$key }
        if ($lab[$key] -is [string]) { $lab[$key] = $lab[$key].Trim() }
    }
    return $lab
}

function Confirm-LabOptions([hashtable]$Lab) {
    if ([string]$Lab.Prefix -notmatch '^([1-9]|[12][0-9]|30)$') { throw 'Use a prefix length from 1 to 30. For subnet mask 255.255.255.0, enter 24.' }
    $server = Convert-LabIPv4 $Lab.ServerIP 'Server IP'
    $client = Convert-LabIPv4 $Lab.ClientIP 'Client IP'
    if ($server -eq $client -or ($server -shr 24) -in 0,127 -or ($server -shr 24) -ge 224 -or
        ($client -shr 24) -in 0,127 -or ($client -shr 24) -ge 224) {
        throw 'Choose two different unicast server and client addresses.'
    }
    $hostCount = [uint64]1 -shl (32 - [int]$Lab.Prefix)
    $mask = [uint64]4294967296 - $hostCount
    $network = $server -band $mask
    $broadcast = $network + $hostCount - 1
    foreach ($address in $server,$client) {
        if ($address -le $network -or $address -ge $broadcast) { throw 'Both PCs need usable host addresses on the same subnet.' }
    }
    $gateway = $null
    if ($Lab.Gateway) {
        $gateway = Convert-LabIPv4 $Lab.Gateway 'Gateway'
        if ($gateway -le $network -or $gateway -ge $broadcast -or $gateway -in $server,$client) {
            throw 'The gateway must be a separate host on the same subnet. Leave it blank for a direct cable without a router.'
        }
    }
    if ($Lab.OU -and $Lab.OU -notmatch '^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$') { throw 'Use letters, numbers, spaces, hyphens or underscores for the OU name.' }
    $users = @()
    $logins = @{}
    $displayNames = @{}
    if ($Lab.Users) {
        if (-not $Lab.OU) { throw 'Enter an OU name before adding domain users.' }
        foreach ($entry in $Lab.Users.Split(',')) {
            $pair = $entry.Trim() -split ':',2
            $display = $pair[0].Trim()
            $login = if ($pair.Count -eq 2) { $pair[1].Trim() } else { $display }
            if ($display -notmatch '^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$' -or
                $login -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,19}$' -or $login -in 'Administrator','Guest','krbtgt','shareuser' -or
                $logins.ContainsKey($login) -or $displayNames.ContainsKey($display)) { throw "Check '$entry'. Use unique names and logins in the format Display Name:login, separated by commas." }
            $logins[$login] = $true
            $displayNames[$display] = $true
            $users += [pscustomobject]@{ Display=$display; Login=$login }
        }
    }
    if ($Lab.DHCP) {
        if ([string]::IsNullOrWhiteSpace($Lab.ScopeName) -or $Lab.ScopeName.Length -gt 64) { throw 'Enter a DHCP scope name of up to 64 characters.' }
        $start = Convert-LabIPv4 $Lab.RangeStart 'DHCP start'
        $end = Convert-LabIPv4 $Lab.RangeEnd 'DHCP end'
        if ($start -gt $end -or $start -le $network -or $end -ge $broadcast) { throw 'The DHCP range must be ordered and inside the usable addresses of the lab subnet.' }
        foreach ($address in $server,$client,$gateway) {
            if ($null -ne $address -and $address -ge $start -and $address -le $end) { throw 'Keep the static server, client and gateway addresses outside the DHCP range.' }
        }
    }
    [pscustomobject]@{ Mask=(Format-LabIPv4 $mask); Network=(Format-LabIPv4 $network); Users=$users }
}
