#requires -Version 4.0
#requires -RunAsAdministrator
param([ValidateSet('Server','Client')][string]$Role, [switch]$Resume)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab-Options.ps1')
$taskName = 'Two-PC Lab - Resume Setup'
$cfgPath = Join-Path $PSScriptRoot 'setup-config.json'
try {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $cfg) { throw 'The settings file is empty.' }
} catch {
    Write-Host 'SETUP STOPPED | Open Setup-GUI.bat to create valid setup settings.' -ForegroundColor Red
    [void](Read-Host 'Press Enter to close')
    exit 1
}
if ($Resume) { $Role = $cfg.Role }
$domain = [string]$cfg.Domain
$short = [string]$cfg.NetBIOS
$name = [string]$cfg.ShareName
$admin = "$short\Administrator"
$group = "$short\PCShareUsers"
$description = "$short two-PC lab managed share"
$lab = Read-LabOptions $cfg.Lab
$serverIP = $lab.ServerIP
$ip = if ($Role -eq 'Server') { $serverIP } else { $lab.ClientIP }
$peer = if ($Role -eq 'Server') { $lab.ClientIP } else { $serverIP }
$local = if ($Resume) { $PSScriptRoot } else { $null }
$hasTask = [bool]$Resume
$usbId = if ($Resume) { $cfg.UsbId } else { Split-Path -Qualifier $PSScriptRoot }
$usbSerial = if ($Resume) { $cfg.UsbSerial } elseif ($cfg.EjectUsb -and $usbId -match '^[A-Z]:$') {
    (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$usbId' and DriveType=2" -ErrorAction SilentlyContinue).VolumeSerialNumber
}

function Restart-ForSetup([string]$phase,[string]$login) {
    $state = @{ Role=$Role; Domain=$domain; NetBIOS=$short; ShareName=$name; ShareDrive=$cfg.ShareDrive
        Adapter=$cfg.Adapter; Discovery=$cfg.Discovery; ReuseEmpty=$cfg.ReuseEmpty; Phase=$phase
        Boot=$os.LastBootUpTime.ToString('o'); EjectUsb=$cfg.EjectUsb; UsbId=$usbId; UsbSerial=$usbSerial; Lab=$lab }
    $state | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'setup-config.json') -Encoding ASCII
    Write-Host "Restarting in 15 seconds. Sign in as $login and setup will continue." -ForegroundColor Yellow
    Start-Sleep -Seconds 15
    Restart-Computer
    exit 0
}

function Register-Resume {
    if ($hasTask) { return }
    $waitingState = @{ Role=$Role; Domain=$domain; NetBIOS=$short; ShareName=$name; ShareDrive=$cfg.ShareDrive
        Adapter=$cfg.Adapter; Discovery=$cfg.Discovery; ReuseEmpty=$cfg.ReuseEmpty
        Boot=$os.LastBootUpTime.ToString('o'); EjectUsb=$cfg.EjectUsb; UsbId=$usbId; UsbSerial=$usbSerial; Lab=$lab }
    $waitingState | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'setup-config.json') -Encoding ASCII
    $worker = Join-Path $local 'Run-Setup.ps1'
    $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument ('-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "' + $worker + '" -Resume') -WorkingDirectory $env:SystemRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-544' -RunLevel Highest
    $options = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $options -Description 'Continues Two-PC Lab setup after an administrator signs in.' | Out-Null
    $script:hasTask = $true
}

function Set-LabIP {
    if ($nic.Status -ne 'Up') { throw 'Connect the selected Ethernet adapter and retry.' }
    Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex -Detailed | Format-List * | Out-File -LiteralPath (Join-Path $local 'network-before.txt')
    Set-NetIPInterface -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -Dhcp Disabled
    Get-NetRoute -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne $ip -or $_.PrefixLength -ne [int]$lab.Prefix } | Remove-NetIPAddress -Confirm:$false
    if (-not (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $ip -ErrorAction SilentlyContinue)) {
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $ip -PrefixLength ([int]$lab.Prefix) | Out-Null
    }
    for ($i=0; $i -lt 15; $i++) {
        $addressState = (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $ip).AddressState
        if ($addressState -eq 'Preferred') {
            if ($lab.Gateway) { New-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -NextHop $lab.Gateway | Out-Null }
            Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $serverIP
            return
        }
        if ($addressState -eq 'Duplicate') { break }
        Start-Sleep -Seconds 1
    }
    throw "The IP $ip did not become usable ($addressState)."
}

function Enable-LabSharing {
    foreach ($binding in 'ms_server','ms_msclient') {
        if (-not (Get-NetAdapterBinding -Name $nic.Name -ComponentID $binding).Enabled) {
            Enable-NetAdapterBinding -Name $nic.Name -ComponentID $binding
        }
    }
    Start-Service LanmanServer
    $ports = ,@('SMB','TCP',445)
    if ($cfg.Discovery) {
        foreach ($service in 'fdPHost','FDResPub') {
            Set-Service -Name $service -StartupType Automatic
            Start-Service -Name $service
        }
        $ports += ,@('WSD','UDP',3702)
        $ports += ,@('WSD-Metadata','TCP',5357)
        $ports += ,@('WSD-Metadata-TLS','TCP',5358)
    }
    foreach ($rule in 'CSSTraining-Lab-SMB','Two-PC-Lab-SMB','Two-PC-Lab-WSD','Two-PC-Lab-WSD-Metadata','Two-PC-Lab-WSD-Metadata-TLS') {
        Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    }
    foreach ($port in $ports) {
        $rule = @{ Name="Two-PC-Lab-$($port[0])"; DisplayName="Two-PC Lab $($port[0])"; Direction='Inbound'
            Protocol=$port[1]; LocalPort=$port[2]; Action='Allow'; Profile='Any'; RemoteAddress=$peer; InterfaceAlias=$nic.Name }
        New-NetFirewallRule @rule | Out-Null
    }
}

function Get-ManagedShare {
    $existing = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
    if ($existing -and ($existing.Description -ne $description -or $existing.Path -ne $folder)) {
        throw "The share '$name' points to '$($existing.Path)' or belongs to another setup. Choose its original drive or a different name."
    }
    $item = Get-Item -LiteralPath $folder -Force -ErrorAction SilentlyContinue
    if ($item) {
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Choose a different name. $folder is a file or link." }
        if (-not $existing -and (-not $cfg.ReuseEmpty -or @(Get-ChildItem -LiteralPath $folder -Force).Count -gt 0)) {
            throw "The folder $folder already exists. Choose another name, or enable repair if it is empty."
        }
    }
    return $existing
}

function Publish-Share {
    $existing = Get-ManagedShare
    $shareAccount = New-Object System.Security.Principal.NTAccount -ArgumentList $group
    $shareSid = $shareAccount.Translate([Security.Principal.SecurityIdentifier])
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($entry in @(@($systemSid,'FullControl'),@($adminSid,'FullControl'),@($shareSid,'Modify'))) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $entry[0],$entry[1],'ContainerInherit,ObjectInherit','None','Allow'
        $acl.AddAccessRule($rule)
    }
    $created = $false
    try {
        if (-not (Test-Path -LiteralPath $folder)) {
            [IO.Directory]::CreateDirectory($folder,$acl) | Out-Null
            $created = $true
        } elseif ($existing) {
            $currentAcl = Get-Acl -LiteralPath $folder
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList $shareSid,'Modify','ContainerInherit,ObjectInherit','None','Allow'
            $currentAcl.SetAccessRule($rule)
            Set-Acl -LiteralPath $folder -AclObject $currentAcl
        } else { Set-Acl -LiteralPath $folder -AclObject $acl }
        if (-not $existing) {
            $adminGroup = $adminSid.Translate([Security.Principal.NTAccount]).Value
            New-SmbShare -Name $name -Path $folder -Description $description -FullAccess $adminGroup -ChangeAccess $group | Out-Null
        } else { Grant-SmbShareAccess -Name $name -AccountName $group -AccessRight Change -Force | Out-Null }
    } catch {
        if ($created -and -not (Get-SmbShare -Name $name -ErrorAction SilentlyContinue)) {
            try { [IO.Directory]::Delete($folder) } catch { Write-Warning "Check the leftover folder $folder before retrying." }
        }
        throw
    }
}
function Request-UsbEject {
    if (-not $cfg.EjectUsb -or -not $usbSerial -or $usbId -notmatch '^[A-Z]:$') { return }
    $device = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$usbId' and DriveType=2"
    if (-not $device -or $device.VolumeSerialNumber -ne $usbSerial) { return }
    $shell = New-Object -ComObject Shell.Application
    $item = $shell.NameSpace(17).ParseName($usbId)
    if (-not $item) { return }
    $eject = $item.Verbs() | Where-Object { $_.Name.Replace('&','').Trim() -eq 'Eject' } | Select-Object -First 1
    if ($eject) {
        $eject.DoIt()
        Write-Host 'Asked Windows to eject the setup USB. Wait for Windows to confirm safe removal.'
    }
}
function Wait-LabDns {
    for ($i=0; $i -lt 15; $i++) {
        try { Resolve-DnsName "_ldap._tcp.dc._msdcs.$domain" -Server $serverIP -Type SRV -DnsOnly -QuickTimeout | Out-Null; return }
        catch { if ($i -eq 14) { throw "Cannot find $domain at $serverIP. Check the cable, server, and Lab options on both PCs." } }
        Start-Sleep -Seconds 2
    }
}

function Initialize-LabUsers {
    if (-not $lab.OU) { return }
    $ouPath = "OU=$($lab.OU),$($ad.DistinguishedName)"
    $ouName = $lab.OU
    $existing = Get-ADOrganizationalUnit -SearchBase $ad.DistinguishedName -SearchScope OneLevel -Filter { Name -eq $ouName }
    if (-not $existing) {
        New-ADOrganizationalUnit -Name $ouName -Path $ad.DistinguishedName
    } else { $ouPath = $existing.DistinguishedName }
    foreach ($student in $validated.Users) {
        $login = $student.Login
        $existing = Get-ADUser -Filter { SamAccountName -eq $login }
        if ($existing) {
            if (-not $existing.DistinguishedName.EndsWith(",$ouPath", [StringComparison]::OrdinalIgnoreCase)) {
                throw "$login already exists outside the selected OU. Choose another login or check the account in Active Directory."
            }
            if (-not $existing.Enabled) { throw "$login exists but is disabled. Set its password and enable it in Active Directory before retrying." }
            Write-Host "Keeping the existing $short\$login account and password."
            continue
        }
        $password = Read-Host "NEW LAB USER | Create the password for $short\$login ($($student.Display))" -AsSecureString
        New-ADUser -Path $ouPath -Name $student.Display -SamAccountName $login -UserPrincipalName "$login@$domain" -AccountPassword $password -Enabled $true -ChangePasswordAtLogon $false
        if ($lab.LabPasswordRules) {
            Set-ADUser -Identity $login -CannotChangePassword $true
            Set-ADUser -Identity $login -PasswordNeverExpires $true
        }
    }
}

function Initialize-LabDhcp {
    if (-not $lab.DHCP) { return }
    $otherLinks = @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceGuid -ne $nic.InterfaceGuid })
    if ($otherLinks.Count) { throw 'Disconnect other active physical adapters before enabling lab DHCP. Keep console access.' }
    $feature = Install-WindowsFeature DHCP -IncludeManagementTools
    if (-not $feature.Success) { throw 'DHCP role installation failed.' }
    if ($feature.RestartNeeded -eq 'Yes') { Register-Resume; Restart-ForSetup 'DhcpInstalled' $admin }
    Import-Module DhcpServer
    Start-Service DHCPServer
    $scopeId = $validated.Network
    $scopes = @(Get-DhcpServerv4Scope)
    if (@($scopes | Where-Object { "$($_.ScopeId)" -ne $scopeId -or
        "$($_.SubnetMask)" -ne $validated.Mask -or "$($_.StartRange)" -ne $lab.RangeStart -or
        "$($_.EndRange)" -ne $lab.RangeEnd -or $_.Name -ne $lab.ScopeName }).Count) {
        throw 'This server already has a different DHCP scope. Review it in DHCP Manager before changing any settings.'
    }
    $binding = Get-DhcpServerv4Binding
    if (-not ($binding | Where-Object InterfaceAlias -eq $nic.Name)) { throw 'DHCP cannot find the selected Ethernet adapter.' }
    foreach ($entry in $binding) {
        Set-DhcpServerv4Binding -InterfaceAlias $entry.InterfaceAlias -BindingState ($entry.InterfaceAlias -eq $nic.Name)
    }
    if (-not $scopes.Count) {
        Add-DhcpServerv4Scope -Name $lab.ScopeName -StartRange $lab.RangeStart -EndRange $lab.RangeEnd -SubnetMask $validated.Mask -State Inactive
    }
    $fqdn = "$env:COMPUTERNAME.$domain"
    $authorized = @(Get-DhcpServerInDC)
    if (@($authorized | Where-Object { ($_.DnsName -eq $fqdn) -xor ("$($_.IPAddress)" -eq $serverIP) }).Count) {
        throw 'An existing DHCP authorization conflicts with this server name or IP. Review it in DHCP Manager.'
    }
    if (-not ($authorized | Where-Object DnsName -eq $fqdn)) { Add-DhcpServerInDC -DnsName $fqdn -IPAddress $serverIP }
    $dhcpOptions = @{ ScopeId=$scopeId; DnsServer=$serverIP; DnsDomain=$domain }
    if ($lab.Gateway) { $dhcpOptions.Router = $lab.Gateway }
    Set-DhcpServerv4OptionValue @dhcpOptions
    Set-DhcpServerv4Scope -ScopeId $scopeId -State Active
    Write-Host "DHCP READY | $($lab.ScopeName): $($lab.RangeStart) to $($lab.RangeEnd)"
}

try {
    $validated = Confirm-LabOptions $lab
    if ($Role -notin 'Server','Client' -or $domain -notmatch '^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$' -or
        $short -notmatch '^[a-z0-9](?:[a-z0-9-]{0,13}[a-z0-9])?$' -or $short -match '^\d+$' -or
        ($lab.CreateShare -and ($name -notmatch '^[a-z0-9][a-z0-9 _-]{0,39}$' -or
        $name -match ' $|^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]|Windows|Users|Program Files|Program Files \(x86\)|ProgramData|Recovery)$' -or
        $cfg.ShareDrive -notmatch '^[A-Z]:$'))) { throw 'Check the domain names, share name, and drive in the GUI.' }

    $os = Get-CimInstance Win32_OperatingSystem
    if ($Resume -and $cfg.Boot -eq $os.LastBootUpTime.ToString('o')) { exit 0 }
    if (-not $Resume -and (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
        throw 'A setup is pending. Restart Windows and sign in as Administrator to resume.'
    }
    $pc = Get-CimInstance Win32_ComputerSystem
    if ($pc.PartOfDomain -and $pc.Domain -ne $domain) { throw "This PC belongs to $($pc.Domain). Use that name or use a fresh lab PC." }
    if ($Role -eq 'Server' -and ($os.ProductType -eq 1 -or [version]$os.Version -lt [version]'6.3' -or ($pc.PartOfDomain -and $pc.DomainRole -lt 4))) { throw 'Server setup requires a fresh Windows Server 2012 R2 or later, or the existing lab controller.' }
    if ($Role -eq 'Client' -and ($os.ProductType -ne 1 -or [version]$os.Version -lt [version]'10.0' -or $os.Caption -notmatch 'Pro|Enterprise|Education')) { throw 'Client setup requires Windows 10 or later Pro, Enterprise, or Education.' }

    if ($lab.CreateShare) {
        $drive = New-Object System.IO.DriveInfo -ArgumentList "$($cfg.ShareDrive)\"
        if (-not $drive.IsReady -or $drive.DriveType -ne 'Fixed' -or $drive.DriveFormat -ne 'NTFS') { throw 'Choose a fixed NTFS drive for the share.' }
        $folder = Join-Path $drive.RootDirectory.FullName $name
        Get-ManagedShare | Out-Null
    }
    $nic = Get-NetAdapter -Physical | Where-Object { "$($_.InterfaceGuid)" -eq $cfg.Adapter -and $_.MediaType -eq '802.3' } | Select-Object -First 1
    if (-not $nic -or $nic.Status -ne 'Up') { throw 'Connect the selected lab Ethernet link before running setup.' }

    if (-not $Resume) {
        $local = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) ('Two-PC-Setup-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $local | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $local 'Run-Setup.ps1')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Lab-Options.ps1') -Destination $local
        Write-Host "Setting up $Role on $env:COMPUTERNAME. $($nic.Name) will use $ip/$($lab.Prefix)."
        Set-LabIP
    }
    if ($Role -eq 'Server') {
        if ($pc.DomainRole -lt 4) {
            if ($cfg.Phase -eq 'Promoted') { throw 'Domain promotion did not take effect after restart.' }
            Register-Resume
            $feature = Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
            if (-not $feature.Success) { throw 'AD DS role installation failed.' }
            if ($feature.RestartNeeded -eq 'Yes') { Restart-ForSetup 'RoleInstalled' 'the local Administrator' }
            $recovery = Read-Host 'DOMAIN RECOVERY | Create a DSRM recovery password' -AsSecureString
            Import-Module ADDSDeployment
            Install-ADDSForest -DomainName $domain -DomainNetbiosName $short -InstallDns -SafeModeAdministratorPassword $recovery -NoRebootOnCompletion -Force | Out-Host
            Restart-ForSetup 'Promoted' $admin
        }
        Wait-LabDns
        Import-Module ActiveDirectory
        $ad = Get-ADDomain -Identity $domain
        if ($ad.NetBIOSName -ne $short) { throw "The existing domain uses the short name $($ad.NetBIOSName)." }
        Initialize-LabDhcp
        Initialize-LabUsers
        if ($lab.CreateShare) {
            if (-not (Get-ADGroup -Filter "SamAccountName -eq 'PCShareUsers'")) { New-ADGroup -Name PCShareUsers -SamAccountName PCShareUsers -GroupScope Global -GroupCategory Security }
            $user = Get-ADUser -Filter "SamAccountName -eq 'shareuser'"
            if ($user -and -not $user.Enabled) { throw "The account $short\shareuser is disabled. Check it in Active Directory before retrying." }
            if (-not $user) {
                $password = Read-Host "SHARE ACCOUNT | Create the sharing password for $short\shareuser" -AsSecureString
                New-ADUser -Name shareuser -SamAccountName shareuser -UserPrincipalName "shareuser@$domain" -AccountPassword $password -Enabled $true
            }
            Add-ADGroupMember -Identity PCShareUsers -Members shareuser
        }
    } else {
        Wait-LabDns
        if (-not $pc.PartOfDomain) {
            if ($cfg.Phase -eq 'Joined') { throw 'The PC did not join the domain after restart.' }
            $credential = Get-Credential -UserName $admin -Message "Enter the server Administrator password to join $domain."
            if (-not $credential) { throw 'Domain join canceled.' }
            Register-Resume
            Add-Computer -DomainName $domain -Credential $credential
            Restart-ForSetup 'Joined' $admin
        }
        if (-not (Test-ComputerSecureChannel)) { throw 'Domain trust check failed. Check the server, DNS, cable, and clocks.' }
    }
    Enable-LabSharing
    if ($lab.CreateShare) { Publish-Share }
    if ($hasTask) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; $hasTask = $false }

    $summary = "$($Role.ToUpperInvariant()) READY. IP $ip/$($lab.Prefix), DNS $serverIP."
    if ($lab.CreateShare) { $summary += " Published \\$env:COMPUTERNAME\$name. Open \\$peer in Explorer to see the other PC's shares." }
    $log = Join-Path $env:ProgramData ((Split-Path -Leaf $local) + '.log')
    $summary | Set-Content -LiteralPath $log -Encoding Unicode
    $localNetwork = Join-Path $local 'network-before.txt'
    if (Test-Path -LiteralPath $localNetwork -PathType Leaf) { Get-Content -LiteralPath $localNetwork | Add-Content -LiteralPath $log -Encoding Unicode }
    foreach ($file in 'Run-Setup.ps1','Lab-Options.ps1','setup-config.json','network-before.txt') {
        $path = Join-Path $local $file
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    [IO.Directory]::Delete($local)
    Write-Host $summary -ForegroundColor Green
    try { Request-UsbEject } catch { Write-Warning 'Windows could not eject the USB automatically.' }
    if ($lab.CreateShare) { Write-Host "Use $short\shareuser if Windows asks for share credentials." }
    Write-Host 'Safely eject the USB in Windows if it is still connected.'
    [void](Read-Host 'Press Enter to close')
} catch {
    Write-Host "SETUP STOPPED | $($_.Exception.Message)" -ForegroundColor Red
    if ($hasTask) {
        try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false } catch { Write-Warning 'Check the Two-PC Lab resume task in Task Scheduler.' }
    }
    if ($local -and (Test-Path -LiteralPath $local -PathType Container)) {
        $_.Exception.Message | Add-Content -LiteralPath (Join-Path $local 'setup-error.log') -ErrorAction SilentlyContinue
        Write-Host "Recovery files: $local. Previous system changes remain."
    }
    [void](Read-Host 'Press Enter to close')
    exit 1
}
