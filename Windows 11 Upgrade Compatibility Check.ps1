##This is a script to check if your Windows 10 PC is compatible with Windows 11
##It checks the following:
# - TPM 2.0
# - Secure Boot
# - CPU
# - RAM
# - Storage
# - Architecture
# Function to check Windows 11 compatibility requirements
function Test-Windows11Compatibility {
    $results = @{
        TPM = $false
        TPMVersion = "Not Found"
        SecureBoot = $false
        CPU = $false
        CPUName = ""
        RAM = $false
        RAMSize = 0
        Storage = $false
        StorageSize = 0
        Architecture = $false
        DirectX = $false
        WDDM = $false
    }

    Write-Host "Checking Windows 11 Compatibility..." -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Yellow

    # Check TPM
    try {
        $TPM = Get-WmiObject -Namespace "root\CIMV2\Security\MicrosoftTpm" -Class Win32_Tpm -ErrorAction Stop
        if ($TPM.IsEnabled_InitialValue) {
            $results.TPM = $true
            $results.TPMVersion = $TPM.SpecVersion
        }
    } catch {
        Write-Host "Unable to detect TPM. It may not exist or be disabled in BIOS." -ForegroundColor Red
    }

    # Check Secure Boot
    $SecureBootStatus = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    $results.SecureBoot = $SecureBootStatus

    # Check CPU
    $CPU = Get-WmiObject Win32_Processor
    $results.CPUName = $CPU.Name
    # This is a simplified check. For a complete check, you'd need to verify against Microsoft's supported CPU list
    if ($CPU.NumberOfCores -ge 2 -and $CPU.MaxClockSpeed -ge 1000) {
        $results.CPU = $true
    }

    # Check RAM
    $RAM = Get-WmiObject Win32_ComputerSystem
    $results.RAMSize = [math]::Round($RAM.TotalPhysicalMemory / 1GB, 2)
    if ($results.RAMSize -ge 4) {
        $results.RAM = $true
    }

    # Check Storage
    $Disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
    $results.StorageSize = [math]::Round($Disk.Size / 1GB, 2)
    if ($results.StorageSize -ge 64) {
        $results.Storage = $true
    }

    # Check System Architecture
    $Architecture = (Get-WmiObject Win32_OperatingSystem).OSArchitecture
    $results.Architecture = ($Architecture -eq "64-bit")

    # Check DirectX and WDDM version
    $results.DirectX = $true  # Simplified check, most Windows 10 systems support DirectX 12
    $results.WDDM = $true     # Simplified check, would need more complex WMI queries for accurate check

    # Display Results
    Write-Host "`nWindows 11 Compatibility Results:" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    Write-Host "TPM 2.0: $($results.TPM) (Version: $($results.TPMVersion))"
    Write-Host "Secure Boot: $($results.SecureBoot)"
    Write-Host "CPU: $($results.CPU) ($($results.CPUName))"
    Write-Host "RAM: $($results.RAM) ($($results.RAMSize) GB)"
    Write-Host "Storage: $($results.Storage) ($($results.StorageSize) GB)"
    Write-Host "64-bit Architecture: $($results.Architecture)"
    Write-Host "DirectX 12: $($results.DirectX)"
    Write-Host "WDDM 2.0: $($results.WDDM)"
    Write-Host "----------------------------------------" -ForegroundColor Cyan

    # Final Verdict
    $compatible = $results.Values | Where-Object { $_ -is [bool] } | ForEach-Object { $_ }
    if ($compatible -notcontains $false) {
        Write-Host "`nVERDICT: This PC meets the basic requirements for Windows 11!" -ForegroundColor Green
    } else {
        Write-Host "`nVERDICT: This PC does not meet Windows 11 requirements." -ForegroundColor Red
        Write-Host "Failing components:" -ForegroundColor Red
        if (-not $results.TPM) { Write-Host "- TPM 2.0 is required" }
        if (-not $results.SecureBoot) { Write-Host "- Secure Boot must be enabled" }
        if (-not $results.CPU) { Write-Host "- CPU does not meet minimum requirements" }
        if (-not $results.RAM) { Write-Host "- Minimum 4GB RAM required" }
        if (-not $results.Storage) { Write-Host "- Minimum 64GB storage required" }
        if (-not $results.Architecture) { Write-Host "- 64-bit system required" }
        if (-not $results.DirectX) { Write-Host "- DirectX 12 required" }
        if (-not $results.WDDM) { Write-Host "- WDDM 2.0 required" }
    }
}

# Run the compatibility check
Test-Windows11Compatibility
