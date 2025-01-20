# Check if the script is running as administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# If not running as administrator, elevate the script
if (-not (Test-Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoExit" -Verb RunAs
    exit
}

Write-Host "Script is running with administrative privileges." -ForegroundColor Green

function Get-Timestamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

try {
    # Get all physical Ethernet adapters excluding Bluetooth and Wi-Fi
    $adapters = Get-WmiObject -Class Win32_NetworkAdapter | Where-Object {
        $_.AdapterType -eq "Ethernet 802.3" -and
        $_.PhysicalAdapter -eq $true -and
        $_.NetConnectionID -ne $null -and
        $_.NetConnectionID -notmatch "WiFi|Wireless|Bluetooth"
    }

    if ($adapters.Count -eq 0) {
        throw "No suitable network adapters found."
    }

    # --- Configuring Device --- 
    Write-Host "--- $(Get-Timestamp) Configuring Device ---" -ForegroundColor Cyan

    # Step 0: Disable Fast Boot
    Write-Host "$(Get-Timestamp) Step 0: Disabling Fast Boot..." -ForegroundColor Yellow
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled " -Value 0 -ErrorAction Stop
    Write-Host "$(Get-Timestamp) Disabled Fast Boot" -ForegroundColor Green

    Write-Host "--- $(Get-Timestamp) Done ---`n" -ForegroundColor Cyan

    foreach ($adapter in $adapters) {
        try {
            Write-Host "`n--- $(Get-Timestamp) Configuring Adapter ---" -ForegroundColor Cyan
            Write-Host "Name: `"$($adapter.Name)`"" -ForegroundColor Yellow
            Write-Host "Description: $($adapter.Description)" -ForegroundColor Yellow
            Write-Host "MAC Address: $($adapter.MACAddress)" -ForegroundColor Yellow
            Write-Host "NetConnectionID: $($adapter.NetConnectionID)" -ForegroundColor Yellow
            Write-Host "PNPDeviceID: $($adapter.PNPDeviceID)" -ForegroundColor Yellow

            if (-not $adapter.PNPDeviceID) {
                throw "Adapter `"$($adapter.Name)`" has no valid PNPDeviceID. Skipping configuration."
            }

            # Registry path for network adapter settings
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\$($adapter.DeviceID.PadLeft(4,'0'))"
            Write-Host "$(Get-Timestamp) Registry path determined for adapter: $regPath"

            # Step 1: Enable WakeOnMagicPacket
            Write-Host "$(Get-Timestamp) Step 1: Enabling WakeOnMagicPacket" -ForegroundColor Yellow
            Set-ItemProperty -Path $regPath -Name "*WakeOnMagicPacket" -Value 1 -ErrorAction Stop
            Write-Host "$(Get-Timestamp) WakeOnMagicPacket successfully enabled." -ForegroundColor Green

            # Step 2: Disable "Allow the computer to turn off this device to save power"
            Write-Host "$(Get-Timestamp) Step 2: Disabling `"Allow the computer to turn off this device to save power`"..." -ForegroundColor Yellow
            Set-ItemProperty -Path $regPath -Name "PnPCapabilities" -Value 24 -ErrorAction Stop
            Write-Host "$(Get-Timestamp) Successfully disabled `"Allow the computer to turn off this device to save power`" option." -ForegroundColor Green

            # Step 3: Enable the device to wake the system
            Write-Host "$(Get-Timestamp) Step 3: Updating device power config to be able to wake the system..." -ForegroundColor Yellow
            powercfg -deviceenablewake "`"$($adapter.Name)`"" | Out-Null
            Write-Host "$(Get-Timestamp) Device wake capability enabled for: `"$($adapter.Name)`"" -ForegroundColor Green

            Write-Host "--- $(Get-Timestamp) Done ---`n" -ForegroundColor Cyan
        }
        catch {
            Write-Error "$(Get-Timestamp) Failed to configure WOL for adapter: `"$($adapter.Name)`". Error: $_"
        }
    }

    Write-Host "`n$(Get-Timestamp) Completed!" -ForegroundColor Cyan
}
catch {
    Write-Warning "$(Get-Timestamp) One or more configurations failed. Please ensure that Wake-on-LAN (WOL) is enabled in the BIOS settings."
    Write-Output "Press any key to continue..."
    [System.Console]::ReadKey() | Out-Null
    exit 1
}

Write-Output "Press any key to continue..."
[System.Console]::ReadKey() | Out-Null
