#requires -Version 4.0
$ErrorActionPreference = 'Stop'
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $windowsName = $os.Caption -replace '^Microsoft\s+', ''
} catch {
    Write-Host 'This helper could not identify this Windows installation. Ask an administrator to check Windows Management Instrumentation (WMI).' -ForegroundColor Red
    exit 1
}

$installation = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name InstallationType -ErrorAction SilentlyContinue).InstallationType
if ($installation -eq 'Server Core') {
    Write-Host "Detected $windowsName (Server Core). This helper needs Windows Server with a graphical desktop." -ForegroundColor Yellow
    exit 1
}

try { Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase }
catch {
    Write-Host "Detected $windowsName, but the Windows desktop libraries could not load. Ask your administrator to check the graphical desktop and .NET Framework installation." -ForegroundColor Red
    exit 1
}

$unboundedSize = New-Object System.Windows.Size -ArgumentList ([double]::PositiveInfinity),([double]::PositiveInfinity)

function Get-CompatibilityProblem($Windows) {
    if ($Windows.ProductType -in 2,3) {
        if ([version]$Windows.Version -lt [version]'6.3') { return 'This server is too old for setup. Use Windows Server 2012 R2 or later.' }
    } elseif ($Windows.ProductType -eq 1) {
        if ([version]$Windows.Version -lt [version]'10.0' -or $Windows.Caption -notmatch '\b(Pro|Enterprise|Education)\b') {
            return 'Client setup needs Windows 10 or later Pro, Enterprise, or Education. Windows Home cannot join the domain.'
        }
    } else { return 'This helper could not identify a supported Windows Server or client edition.' }
}

. (Join-Path $PSScriptRoot 'Lab-Options.ps1')
$configFile = Join-Path $PSScriptRoot 'setup-config.json'
$settings = $null
$configNotice = $null
if (Test-Path -LiteralPath $configFile) {
    try { $settings = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json }
    catch { $configNotice = 'Saved settings could not be read. Check the defaults before starting.' }
}
$script:lab = Read-LabOptions $settings.Lab

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="P2P Server Client Setup" WindowStartupLocation="CenterScreen"
        SizeToContent="WidthAndHeight" ResizeMode="CanMinimize"
        Background="#F1F5F9" FontFamily="Segoe UI" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="Padding" Value="14"/>
        </Style>
        <Style x:Key="Section" TargetType="TextBlock">
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#0F172A"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#334155"/>
            <Setter Property="Padding" Value="0,0,0,4"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="7,4"/>
            <Setter Property="MinHeight" Value="29"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="6,3"/>
            <Setter Property="MinHeight" Value="29"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#334155"/>
            <Setter Property="Margin" Value="0,4,0,2"/>
            <Setter Property="MinHeight" Value="21"/>
        </Style>
        <Style x:Key="Action" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="MinHeight" Value="36"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Surface" Background="{TemplateBinding Background}"
                                BorderBrush="Transparent" BorderThickness="2" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.88"/></Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="BorderBrush" Value="#FDE68A"/></Trigger>
                            <Trigger Property="IsPressed" Value="True"><Setter TargetName="Surface" Property="Opacity" Value="0.74"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Surface" Property="Background" Value="#E2E8F0"/>
                                <Setter Property="Foreground" Value="#475569"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <StackPanel x:Name="Page" Width="712" Background="#F1F5F9">
        <Border Background="#0F172A" Padding="18,12">
            <DockPanel LastChildFill="True">
                <TextBlock x:Name="RoleBadge" DockPanel.Dock="Right" VerticalAlignment="Center"
                           Foreground="#A5D6FF" FontWeight="SemiBold" Margin="14,0,0,0"/>
                <StackPanel>
                    <TextBlock Text="P2P Server Client Setup" Foreground="White" FontSize="22" FontWeight="SemiBold"/>
                    <TextBlock x:Name="ComputerDetails" Foreground="#CBD5E1" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <StackPanel Margin="16,12,16,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Domain and folder" Style="{StaticResource Section}"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="114"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <Label Content="_DNS domain" Target="{Binding ElementName=DomainBox}"/>
                                <TextBox x:Name="DomainBox" MaxLength="253" AutomationProperties.Name="DNS domain"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2">
                                <Label Content="S_hort name" Target="{Binding ElementName=ShortBox}"/>
                                <TextBox x:Name="ShortBox" MaxLength="15" CharacterCasing="Upper" AutomationProperties.Name="Short domain name"/>
                            </StackPanel>
                        </Grid>
                        <TextBlock x:Name="LoginPreview" Foreground="#475569" Margin="0,6,0,10" TextTrimming="CharacterEllipsis"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="92"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel>
                                <Label Content="Share _name" Target="{Binding ElementName=ShareBox}"/>
                                <TextBox x:Name="ShareBox" MaxLength="40" AutomationProperties.Name="Share name"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2">
                                <Label Content="Dri_ve" Target="{Binding ElementName=DriveBox}"/>
                                <ComboBox x:Name="DriveBox" DisplayMemberPath="Letter" AutomationProperties.Name="Share drive"/>
                            </StackPanel>
                        </Grid>
                        <TextBlock x:Name="SharePreview" Foreground="#475569" Margin="0,6,0,0" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="2" Style="{StaticResource Card}">
                    <StackPanel>
                        <TextBlock Text="Ethernet and sharing" Style="{StaticResource Section}"/>
                        <Label Content="Lab _Ethernet adapter" Target="{Binding ElementName=AdapterBox}"/>
                        <Grid Margin="0,0,0,6">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ComboBox x:Name="AdapterBox" DisplayMemberPath="Name" AutomationProperties.Name="Connected Ethernet adapter"/>
                            <Button x:Name="RefreshButton" Grid.Column="2" Padding="8,2" Content="_Refresh"
                                    ToolTip="Refresh connected Ethernet adapters and local NTFS drives"/>
                        </Grid>
                        <CheckBox x:Name="DiscoveryBox" Content="Show this PC in Explorer Network"/>
                        <CheckBox x:Name="RepairBox" Content="Reuse an empty leftover share folder"/>
                        <CheckBox x:Name="EjectBox" Content="Request safe USB eject after setup"/>
                    </StackPanel>
                </Border>
            </Grid>

            <DockPanel Margin="0,10,0,0">
                <Button x:Name="LabOptionsButton" DockPanel.Dock="Right" Padding="10,4" Content="_Lab options"/>
                <TextBlock x:Name="LabSummary" Foreground="#334155" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,10,0"/>
            </DockPanel>
            <TextBlock Text="Connect just two lab PCs with a crossover Ethernet cable. Save your work before starting. Windows may restart automatically."
                       Foreground="#334155" TextWrapping="Wrap" Margin="0,10,0,8"/>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="ServerButton" Style="{StaticResource Action}" Background="#1D4ED8"
                        Content="Set up _server   192.168.1.1"/>
                <Button x:Name="ClientButton" Grid.Column="2" Style="{StaticResource Action}" Background="#047857"
                        Content="Set up _client   192.168.1.2"/>
            </Grid>
        </StackPanel>

        <Border Background="#FFFFFF" BorderBrush="#CBD5E1" BorderThickness="0,1,0,0" Padding="16,8">
            <DockPanel LastChildFill="True">
                <TextBlock DockPanel.Dock="Right" Margin="14,0,0,0" VerticalAlignment="Center">
                    <Hyperlink x:Name="CreditLink" Foreground="#1D4ED8" NavigateUri="https://github.com/10yukine">By @10yukine</Hyperlink>
                </TextBlock>
                <TextBlock x:Name="StatusText" TextWrapping="Wrap" Foreground="#334155" VerticalAlignment="Center"/>
            </DockPanel>
        </Border>
    </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
foreach ($id in 'Page','RoleBadge','ComputerDetails','DomainBox','ShortBox','LoginPreview','ShareBox',
    'DriveBox','SharePreview','AdapterBox','RefreshButton','DiscoveryBox','RepairBox','EjectBox',
    'ServerButton','ClientButton','CreditLink','StatusText','LabOptionsButton','LabSummary') {
    Set-Variable -Name $id -Value $window.FindName($id)
}

function Update-LabSummary {
    $ServerButton.Content = "Set up _server   $($script:lab.ServerIP)"
    $ClientButton.Content = "Set up _client   $($script:lab.ClientIP)"
    $LabSummary.Text = "Prefix /$($script:lab.Prefix)   |   DNS $($script:lab.ServerIP)   |   OU " +
        $(if ($script:lab.OU) { $script:lab.OU } else { 'none' })
}

function Show-LabOptions {
    $dialog = New-Object System.Windows.Window
    $dialog.Title = 'Lab options'
    $dialog.Owner = $window
    $dialog.WindowStartupLocation = 'CenterOwner'
    $dialog.SizeToContent = 'WidthAndHeight'
    $dialog.ResizeMode = 'NoResize'
    $dialog.FontFamily = $window.FontFamily
    $dialog.FontSize = $window.FontSize
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Width = 620
    $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 16
    $dialog.Content = $panel
    $controls = @{}
    $savedUsers = @(Get-LabUserEntries $script:lab.Users)
    $userFields = @{
        FirstDisplay = $savedUsers[0].Display
        FirstLogin = $savedUsers[0].Login
        SecondDisplay = $savedUsers[1].Display
        SecondLogin = $savedUsers[1].Login
    }
    $extraUsers = @($savedUsers | Select-Object -Skip 2 -ExpandProperty Entry)
    $secondUser = New-Object System.Windows.Controls.CheckBox
    $secondUser.Content = 'Add User 2 (optional)'
    $secondUser.IsChecked = $savedUsers.Count -ge 2
    $secondUser.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,4
    $pairs = @(
        @('ServerIP','Server IPv4','ClientIP','Client IPv4'),
        @('Prefix','Subnet prefix (24 = 255.255.255.0)','Gateway','Gateway (optional)'),
        @('RangeStart','DHCP range start','RangeEnd','DHCP range end'),
        @('ScopeName','DHCP scope name','OU','OU name (required for users)'),
        @('FirstDisplay','User 1 display name','FirstLogin','User 1 sign-in name'),
        @('SecondDisplay','User 2 display name','SecondLogin','User 2 sign-in name')
    )
    foreach ($pair in $pairs) {
        if ($pair[0] -eq 'SecondDisplay') { [void]$panel.Children.Add($secondUser) }
        $row = New-Object System.Windows.Controls.Primitives.UniformGrid
        $row.Columns = 2
        [void]$panel.Children.Add($row)
        for ($i=0; $i -lt $pair.Count; $i+=2) {
            $field = New-Object System.Windows.Controls.StackPanel
            $field.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,8,8
            $label = New-Object System.Windows.Controls.Label
            $label.Padding = New-Object System.Windows.Thickness -ArgumentList 0,0,0,3
            $label.Content = $pair[$i+1]
            $box = New-Object System.Windows.Controls.TextBox
            $box.MinHeight = 26
            $key = $pair[$i]
            $box.Text = if ($userFields.ContainsKey($key)) { [string]$userFields[$key] } else { [string]$script:lab[$key] }
            $label.Target = $box
            $controls[$key] = $box
            [void]$field.Children.Add($label)
            [void]$field.Children.Add($box)
            [void]$row.Children.Add($field)
        }
    }
    $controls.SecondDisplay.IsEnabled = $secondUser.IsChecked
    $controls.SecondLogin.IsEnabled = $secondUser.IsChecked
    $secondUser.Add_Checked({ $controls.SecondDisplay.IsEnabled = $controls.SecondLogin.IsEnabled = $true }.GetNewClosure())
    $secondUser.Add_Unchecked({ $controls.SecondDisplay.IsEnabled = $controls.SecondLogin.IsEnabled = $false }.GetNewClosure())
    foreach ($option in @(
        @('CreateShare','Create the basic file share on both PCs'),
        @('DHCP','Install and configure IPv4 DHCP on the server'),
        @('LabPasswordRules','For new lab users: passwords never expire and users cannot change them')
    )) {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = $option[1]
        $box.IsChecked = [bool]$script:lab[$option[0]]
        $box.Margin = New-Object System.Windows.Thickness -ArgumentList 0,3,0,3
        $controls[$option[0]] = $box
        [void]$panel.Children.Add($box)
    }
    $tip = New-Object System.Windows.Controls.TextBlock
    $tip.Text = 'DNS uses the server IP. Leave gateway blank on a direct cable. Leave User 1 blank to skip new accounts.'
    if ($extraUsers.Count) { $tip.Text += " Your saved profile also has $($extraUsers.Count) additional domain user(s)." }
    $tip.TextWrapping = 'Wrap'
    $tip.Margin = New-Object System.Windows.Thickness -ArgumentList 0,8,0,8
    [void]$panel.Children.Add($tip)
    $save = New-Object System.Windows.Controls.Button
    $save.Content = 'Apply lab options'
    $save.IsDefault = $true
    $save.MinHeight = 30
    [void]$panel.Children.Add($save)
    $result = @{ Lab = $null }
    $save.Add_Click({
        try {
            $candidate = @{}
            foreach ($key in (Get-LabDefaults).Keys) {
                if ($key -eq 'Users') { continue }
                $candidate[$key] = if ($controls[$key] -is [Windows.Controls.CheckBox]) { [bool]$controls[$key].IsChecked } else { $controls[$key].Text.Trim() }
            }
            $entries = @()
            foreach ($slot in 'First','Second') {
                if ($slot -eq 'Second' -and -not $secondUser.IsChecked) { continue }
                $display = $controls["${slot}Display"].Text.Trim()
                $login = $controls["${slot}Login"].Text.Trim()
                $number = if ($slot -eq 'First') { 1 } else { 2 }
                if ($number -eq 1 -and -not ($display -or $login)) {
                    if ($secondUser.IsChecked) { throw 'Enter User 1 before adding User 2.' }
                    continue
                }
                if (-not ($display -and $login)) { throw "Enter both names for User $number." }
                if ($display -match '[:,]' -or $login -match '[:,]') { throw "Remove commas and colons from User $number." }
                $entries += "${display}:$login"
            }
            $candidate.Users = ($entries + $extraUsers) -join ','
            [void](Confirm-LabOptions $candidate)
            $result.Lab = $candidate
            $dialog.DialogResult = $true
        } catch {
            [void][Windows.MessageBox]::Show($dialog, $_.Exception.Message, 'Check lab options', 'OK', 'Warning')
        }
    }.GetNewClosure())
    $panel.Measure($unboundedSize)
    $work = [Windows.SystemParameters]::WorkArea
    $factor = [math]::Min(1.0,[math]::Min(($work.Width-28)/$panel.DesiredSize.Width,($work.Height-56)/$panel.DesiredSize.Height))
    if ($factor -lt 1) { $panel.LayoutTransform = New-Object System.Windows.Media.ScaleTransform -ArgumentList $factor,$factor }
    if ($dialog.ShowDialog()) {
        $script:lab = $result.Lab
        Update-LabSummary
        Update-Preview
        Set-Status 'Lab options applied. Both PCs must use the same network settings.'
    }
}

function Set-Status([string]$Message, [switch]$Problem) {
    $StatusText.Text = $Message
    $StatusText.Foreground = if ($Problem) { [Windows.Media.Brushes]::Firebrick } else { [Windows.Media.Brushes]::DarkSlateGray }
}

function Update-Preview {
    $shortName = $ShortBox.Text.Trim().ToUpperInvariant()
    $LoginPreview.Text = if ($shortName) { "Admin sign-in  $shortName\Administrator" } else { 'Enter the short name to preview sign-in.' }
    $path = if ($DriveBox.SelectedItem -and $ShareBox.Text.Trim()) {
        "$($DriveBox.SelectedItem.Letter)\$($ShareBox.Text.Trim())"
    }
    $SharePreview.Text = if ($path) { "Share folder  $path" } else { 'Choose a local NTFS drive and share name.' }
    $SharePreview.ToolTip = $path
}

function Refresh-Hardware {
    $selectedDrive = if ($DriveBox.SelectedItem) { $DriveBox.SelectedItem.Letter } elseif ($settings.ShareDrive) { $settings.ShareDrive } else { $env:SystemDrive }
    $selectedAdapter = if ($AdapterBox.SelectedItem) { [string]$AdapterBox.SelectedItem.InterfaceGuid } else { [string]$settings.Adapter }

    $DriveBox.ItemsSource = @([IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and $_.DriveType -eq 'Fixed' -and $_.DriveFormat -eq 'NTFS'
    } | ForEach-Object { [pscustomobject]@{ Letter = $_.Name.TrimEnd('\') } })
    $DriveBox.SelectedItem = $DriveBox.Items | Where-Object Letter -eq $selectedDrive | Select-Object -First 1
    if ($DriveBox.SelectedIndex -lt 0 -and $DriveBox.Items.Count -eq 1) { $DriveBox.SelectedIndex = 0 }

    $AdapterBox.ItemsSource = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $_.MediaType -eq '802.3' -and $_.Status -eq 'Up'
    })
    $AdapterBox.SelectedItem = $AdapterBox.Items | Where-Object { [string]$_.InterfaceGuid -eq $selectedAdapter } | Select-Object -First 1
    if ($AdapterBox.SelectedIndex -lt 0 -and $AdapterBox.Items.Count -eq 1) { $AdapterBox.SelectedIndex = 0 }
    if ($compatibilityProblem) { Set-Status $compatibilityProblem -Problem }
    elseif (-not $AdapterBox.Items.Count) { Set-Status 'Connect the lab Ethernet cable, then click Refresh.' -Problem }
    else { Set-Status 'Set up the server first. Wait for SERVER READY before setting up the client.' }
    Update-Preview
}

function Start-LabSetup([ValidateSet('Server','Client')][string]$Role) {
    if ($compatibilityProblem) { Set-Status $compatibilityProblem -Problem; return }
    $domain = $DomainBox.Text.Trim().TrimEnd('.').ToLowerInvariant()
    $netbios = $ShortBox.Text.Trim().ToUpperInvariant()
    $shareName = $ShareBox.Text.Trim()
    if ($domain -notmatch '^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$') {
        Set-Status 'Enter a DNS domain such as server.local.' -Problem
        [void]$DomainBox.Focus()
        return
    }
    if ($netbios -notmatch '^[a-z0-9](?:[a-z0-9-]{0,13}[a-z0-9])?$' -or $netbios -match '^\d+$') {
        Set-Status 'Use 1 to 15 letters, numbers or internal hyphens for the short name. Include a letter.' -Problem
        [void]$ShortBox.Focus()
        return
    }
    if ($script:lab.CreateShare -and ($shareName -notmatch '^[a-z0-9][a-z0-9 _-]{0,39}$' -or
        $shareName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]|Windows|Users|Program Files|Program Files \(x86\)|ProgramData|Recovery)$')) {
        Set-Status 'Choose a share name with letters, numbers, spaces, hyphens or underscores.' -Problem
        [void]$ShareBox.Focus()
        return
    }
    if ($script:lab.CreateShare -and -not $DriveBox.SelectedItem) { Set-Status 'Select a local NTFS drive.' -Problem; [void]$DriveBox.Focus(); return }
    if (-not $AdapterBox.SelectedItem) { Set-Status 'Select the connected lab Ethernet adapter.' -Problem; [void]$AdapterBox.Focus(); return }
    if ($detectedRole -and $Role -ne $detectedRole) {
        Set-Status "This PC runs the $detectedRole edition of Windows. Choose $detectedRole setup." -Problem
        return
    }
    $worker = Join-Path $PSScriptRoot 'Run-Setup.ps1'
    if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) { Set-Status 'Run-Setup.ps1 is missing from _assets.' -Problem; return }
    $current = @{
        Domain = $domain; NetBIOS = $netbios; ShareDrive = $DriveBox.SelectedItem.Letter
        ShareName = $shareName; Adapter = [string]$AdapterBox.SelectedItem.InterfaceGuid
        Discovery = [bool]$DiscoveryBox.IsChecked; ReuseEmpty = [bool]$RepairBox.IsChecked
        EjectUsb = [bool]$EjectBox.IsChecked
        Lab = $script:lab
    }
    try {
        $current | ConvertTo-Json -Compress | Set-Content -LiteralPath $configFile -Encoding ASCII
        $arguments = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "' + $worker + '" -Role ' + $Role
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WorkingDirectory $env:SystemRoot -Verb RunAs
        $window.Close()
    }
    catch { Set-Status "Setup could not start. $($_.Exception.Message)" -Problem }
}

$DomainBox.Text = if ($settings.Domain) { $settings.Domain } else { 'csstraining.com' }
$ShortBox.Text = if ($settings.NetBIOS) { $settings.NetBIOS } else { 'CSSTRAINING' }
$ShareBox.Text = if ($settings.ShareName) { $settings.ShareName } else { 'PCShare' }
$DiscoveryBox.IsChecked = if ($settings -and $settings.PSObject.Properties['Discovery']) { [bool]$settings.Discovery } else { $true }
$EjectBox.IsChecked = if ($settings -and $settings.PSObject.Properties['EjectUsb']) { [bool]$settings.EjectUsb } else { $true }
$detectedRole = if ($os.ProductType -eq 1) { 'Client' } elseif ($os.ProductType -in 2,3) { 'Server' }
$compatibilityProblem = Get-CompatibilityProblem $os
$RoleBadge.Text = if ($compatibilityProblem) { 'Setup unavailable' } else { "$detectedRole PC" }
$ComputerDetails.Text = "$env:COMPUTERNAME | $windowsName"
$ServerButton.IsEnabled = -not $compatibilityProblem -and $detectedRole -eq 'Server'
$ClientButton.IsEnabled = -not $compatibilityProblem -and $detectedRole -eq 'Client'

$DomainBox.Add_TextChanged({ Update-Preview })
$ShortBox.Add_TextChanged({ Update-Preview })
$ShareBox.Add_TextChanged({ Update-Preview })
$DriveBox.Add_SelectionChanged({ Update-Preview })
$RefreshButton.Add_Click({ Refresh-Hardware })
$LabOptionsButton.Add_Click({ Show-LabOptions })
$ServerButton.Add_Click({ Start-LabSetup 'Server' })
$ClientButton.Add_Click({ Start-LabSetup 'Client' })
$CreditLink.Add_RequestNavigate({
    param($sender, $eventArgs)
    $eventArgs.Handled = $true
    try { Start-Process $eventArgs.Uri.AbsoluteUri }
    catch { Set-Status "Could not open GitHub. $($_.Exception.Message)" -Problem }
})

Refresh-Hardware
Update-LabSummary
if ($configNotice -and -not $compatibilityProblem) { Set-Status $configNotice -Problem }

# Size to the content and scale down only when the Windows work area is smaller.
$Page.Measure($unboundedSize)
$workArea = [Windows.SystemParameters]::WorkArea
$scale = [Math]::Min(1.0, [Math]::Min(($workArea.Width - 24) / $Page.DesiredSize.Width,
    ($workArea.Height - 50) / $Page.DesiredSize.Height))
if ($scale -lt 1) { $Page.LayoutTransform = New-Object System.Windows.Media.ScaleTransform -ArgumentList $scale,$scale }
[void]$window.ShowDialog()
