# Check if the script is running as administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Elevate the script if not running as administrator
if (-not (Test-Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -NoExit" -Verb RunAs
    exit
}

Write-Host "Script is running with administrative privileges." -ForegroundColor Green

function Get-Timestamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

try {
    # Disable Fast Boot
    try {
        Write-Host "$(Get-Timestamp) Disabling Fast Boot.." -ForegroundColor Yellow
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled " -Value 0 -ErrorAction Stop
        Write-Host "$(Get-Timestamp) Fast Boot disabled." -ForegroundColor Green
    }
    catch {
        Write-Error "$(Get-Timestamp) Failed to disable Fast Boot."
        Write-Error "`n`nDue to: $_"
        throw ""
    }

    # List all physical Ethernet adapters
    $physicalAdapters = Get-NetAdapter -Name "Ethernet*" -Physical

    foreach ($adapter in $physicalAdapters) {
        try {
            # Get detailed power management properties for current adapter
            $power = $adapter | Get-NetAdapterPowerManagement
            $fullDeviceName = $adapter.InterfaceDescription

            # --- Configuring adapter ---
            Write-Host "--- $(Get-Timestamp) Configuring `"$fullDeviceName`" adapter ---" -ForegroundColor Cyan

            $adapter | Format-List -Property *

            # Step 1: Enable WakeOnMagicPacket
            Write-Host "$(Get-Timestamp) Step 1: Enabling WakeOnMagicPacket.." -ForegroundColor Yellow
            $power.WakeOnMagicPacket = 'Enabled'
            $power | Set-NetAdapterPowerManagement
            Write-Host "$(Get-Timestamp) WakeOnMagicPacket successfully enabled." -ForegroundColor Green

            # Step 2: Disable "Allow the computer to turn off this device to save power"
            Write-Host "$(Get-Timestamp) Step 2: Disabling `"Allow the computer to turn off this device to save power`".." -ForegroundColor Yellow
            $power.AllowComputerToTurnOffDevice = 'Disabled'
            $power | Set-NetAdapterPowerManagement
            Write-Host "$(Get-Timestamp) Successfully disabled `"Allow the computer to turn off this device to save power`" option." -ForegroundColor Green

            # Step 3: Enable the device to wake the system from a sleep state
            Write-Host "$(Get-Timestamp) Step 3: Enabling the device to wake the system from a sleep state.." -ForegroundColor Yellow
            powercfg -deviceenablewake "`"$fullDeviceName`""
            Write-Host "$(Get-Timestamp) Enabled the device to wake the system from a sleep state." -ForegroundColor Green

            $power | Format-List -Property *

            Write-Host "--- $(Get-Timestamp) `"$fullDeviceName`" adapter configured! ---`n" -ForegroundColor Cyan
        } catch {
            Write-Error "$(Get-Timestamp) Failed to configure WOL for adapter: `"$($adapter.Name)`""
            Write-Error "`n`nDue to: $_"
        }
    }

    Write-Host "`n$(Get-Timestamp) OS WoL configuration completed! Remember to turn on BIOS `"Power On By PCIe`" option." -ForegroundColor Green
} catch {
    Write-Warning "$(Get-Timestamp) One or more configurations failed. Terminating..."
    Write-Output "Press any key to continue..."
    [System.Console]::ReadKey() | Out-Null
    exit 1
}

Write-Output "Press any key to continue..."
[System.Console]::ReadKey() | Out-Null
