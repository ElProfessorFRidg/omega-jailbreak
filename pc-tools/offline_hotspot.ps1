# offline_hotspot.ps1 - Windows Mobile Hotspot with NO internet ("dead" Wi-Fi).
#
# The hotspot shares a connection that has no internet (default: the unplugged
# "Ethernet" profile), so the iPad joins a real Wi-Fi network but can't reach
# anything - in particular Apple's OCSP / PPQ revocation servers. Use it so the
# iPad stays "on Wi-Fi" across the Omega restore and reboot without being able
# to re-check / re-revoke certificates.
#
# Must run in Windows PowerShell 5.1 (powershell.exe), not pwsh 7 (no WinRT).
#   powershell -ExecutionPolicy Bypass -File offline_hotspot.ps1 -Action start
#   powershell -ExecutionPolicy Bypass -File offline_hotspot.ps1 -Action status
#   powershell -ExecutionPolicy Bypass -File offline_hotspot.ps1 -Action stop
param(
    [ValidateSet("start", "stop", "status")] [string]$Action = "status",
    [string]$SourceProfile = "Ethernet",
    [string]$Ssid = "Omega-Offline",
    [string]$Passphrase = "omegaoffline"
)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]

# Await a WinRT IAsyncOperation / IAsyncAction from PowerShell.
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$resultType) {
    $task = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    $task.Result
}
function AwaitAction($op) {
    $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
    $asTask.Invoke($null, @($op)).Wait(-1) | Out-Null
}

$profile = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles() |
    Where-Object { $_.ProfileName -eq $SourceProfile } | Select-Object -First 1
if (-not $profile) { Write-Error "Connection profile '$SourceProfile' not found."; exit 1 }

$level = $profile.GetNetworkConnectivityLevel()
if ($level -eq "InternetAccess") {
    Write-Warning "'$SourceProfile' HAS internet access - the hotspot would NOT be offline. Pick a profile with no internet."
    if ($Action -eq "start") { exit 1 }
}

$mgr = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)

switch ($Action) {
    "status" {
        $cfg = $mgr.GetCurrentAccessPointConfiguration()
        "Source      : $SourceProfile (connectivity: $level)"
        "State       : $($mgr.TetheringOperationalState)"
        "SSID        : $($cfg.Ssid)"
        "Clients     : $($mgr.ClientCount) / $($mgr.MaxClientCount)"
    }
    "start" {
        $cfg = New-Object Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration
        $cfg.Ssid = $Ssid
        $cfg.Passphrase = $Passphrase
        AwaitAction ($mgr.ConfigureAccessPointAsync($cfg))
        $res = Await ($mgr.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        "Start result: $($res.Status) $($res.AdditionalErrorMessage)"
        "State       : $($mgr.TetheringOperationalState)"
        "Join on iPad: SSID '$Ssid'  password '$Passphrase'  (no internet behind it)"
    }
    "stop" {
        $res = Await ($mgr.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        "Stop result : $($res.Status) $($res.AdditionalErrorMessage)"
        "State       : $($mgr.TetheringOperationalState)"
    }
}
