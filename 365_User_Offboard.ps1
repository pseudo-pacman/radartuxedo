<#
.SYNOPSIS
Automates the initial steps of offboarding a Microsoft 365 user.
Disables sign-in, resets password, revokes sessions, and converts the user mailbox to shared.

.DESCRIPTION
This script prompts for the User Principal Name (UPN) of the user to offboard.
It performs the following actions:
1. Connects to Microsoft Graph and Exchange Online.
2. Disables the user's account sign-in.
3. Resets the user's password to a random, complex value (not displayed or stored).
4. Revokes all active Microsoft Graph sign-in sessions.
5. Converts the user's mailbox to a Shared Mailbox.

Requires the Microsoft.Graph and ExchangeOnlineManagement modules.
Run with appropriate admin privileges (e.g., User Admin, Exchange Admin, Global Admin).

.PARAMETER UserPrincipalName
The email address (UPN) of the user to offboard. You will be prompted for this.

.EXAMPLE
.\Offboard-M365User.ps1
# Prompts for the user's UPN and executes the offboarding steps.

.NOTES
Author: pseudo-pacman
Date:   2025-04-09
Version: 1.0

- Does NOT remove the user's license. This should be done manually after verifying the shared mailbox.
- Test thoroughly on a non-production account first.
- Mailbox conversion may fail if Litigation Hold or certain Retention Policies are active.
#>

#Requires -Modules Microsoft.Graph, ExchangeOnlineManagement

#region Module Check and Import
Write-Host "Checking for required PowerShell modules..." -ForegroundColor Cyan

# Check for Microsoft.Graph module
if (-not (Get-Module Microsoft.Graph -ListAvailable)) {
    Write-Warning "Microsoft.Graph module not found."
    Write-Host "Please install it by running in an Administrator PowerShell window: Install-Module Microsoft.Graph -Force" -ForegroundColor Yellow
    # Consider adding -AllowClobber if needed, or handle scope (CurrentUser vs AllUsers)
    return # Stop script execution if module is missing
}

# Check for ExchangeOnlineManagement module
if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
    Write-Warning "ExchangeOnlineManagement module not found."
    Write-Host "Please install it by running in an Administrator PowerShell window: Install-Module ExchangeOnlineManagement -Force" -ForegroundColor Yellow
    return # Stop script execution if module is missing
}

# Import necessary modules
Write-Host "Importing required modules..." -ForegroundColor Cyan
# Suppress verbose output during import if desired
Import-Module Microsoft.Graph -ErrorAction Stop
Import-Module ExchangeOnlineManagement -ErrorAction Stop

Write-Host "Modules loaded successfully." -ForegroundColor Green
#endregion

#region Connect to Services
Write-Host "Connecting to Microsoft 365 services (Graph and Exchange Online)..." -ForegroundColor Cyan

# Define required scopes for Microsoft Graph actions
# User.ReadWrite.All is needed for updating user properties (disable, password) and revoking sessions.
$graphScopes = @("User.ReadWrite.All", "Directory.AccessAsUser.All")

try {
    # Check existing connections first to avoid multiple prompts if already connected
    $mgContext = Get-MgContext -ErrorAction SilentlyContinue
    $exoSession = Get-PSSession | Where-Object { $_.ConfigurationName -eq 'Microsoft.Exchange' } -ErrorAction SilentlyContinue

    if (-not $mgContext) {
        Write-Host "Connecting to Microsoft Graph..."
        # Connect to Microsoft Graph - Will prompt for credentials if not already connected
        Connect-MgGraph -Scopes $graphScopes -ErrorAction Stop
    } else {
        Write-Host "Already connected to Microsoft Graph as ($($mgContext.Account))." -ForegroundColor Green
    }

    if (-not $exoSession) {
         Write-Host "Connecting to Exchange Online..."
        # Connect to Exchange Online - Will prompt for credentials if not already connected
        # Using -ShowBanner:$false for cleaner output
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    } else {
         Write-Host "Already connected to Exchange Online." -ForegroundColor Green
    }


    Write-Host "Successfully connected/verified connection to Microsoft Graph and Exchange Online." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft 365 services. Please ensure you have permissions and modules are working correctly."
    Write-Error "Specific Error: $($_.Exception.Message)"
    # Attempt graceful disconnect if partial connection occurred
    if (Get-MgContext -ErrorAction SilentlyContinue) { Disconnect-MgGraph }
    if (Get-PSSession | Where-Object { $_.ConfigurationName -eq 'Microsoft.Exchange' }) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue }
    return # Stop script execution on connection failure
}
#endregion

#region Get User Input
$userUPN = $null
while (-not $userUPN -or $userUPN -notlike '*@*') {
    $userUPN = Read-Host "STEP 1: Please enter the User Principal Name (email address) of the user to offboard"
    if ($userUPN -notlike '*@*') {
        Write-Warning "Invalid format. Please enter a valid email address (e.g., user@domain.com)."
    }
}
#endregion

#region Core Offboarding Logic
Write-Host "`nStarting offboarding process for: $userUPN" -ForegroundColor Yellow

# Get the Graph User Object first to ensure the user exists
try {
    Write-Host "Verifying user account..." -ForegroundColor Cyan
    $mgUser = Get-MgUser -UserId $userUPN -ErrorAction Stop
    Write-Host "Found user: $($mgUser.DisplayName) (ID: $($mgUser.Id))" -ForegroundColor Green
}
catch {
    Write-Error "Could not find user with UPN '$userUPN'. Please check the UPN and try again."
    Write-Error "Specific Error: $($_.Exception.Message)"
    # Disconnect before exiting
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    return # Stop script execution if user not found
}

# --- Action 1: Disable Sign-in ---
Write-Host "`nSTEP 2: Attempting to disable sign-in for $userUPN..." -ForegroundColor Cyan
try {
    # Check if already disabled
    if ($mgUser.AccountEnabled) {
        Update-MgUser -UserId $mgUser.Id -AccountEnabled:$false -ErrorAction Stop
        Write-Host "[SUCCESS] Sign-in disabled for $userUPN." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Sign-in was already disabled for $userUPN." -ForegroundColor Cyan
    }
}
catch {
    Write-Warning "[FAILED] Could not disable sign-in for $userUPN."
    Write-Warning "Specific Error: $($_.Exception.Message)"
    # Consider adding a confirmation here to continue or stop script based on requirements
}

# --- Action 2: Reset Password ---
Write-Host "`nSTEP 3: Attempting to reset password for $userUPN..." -ForegroundColor Cyan
# Generate a complex random password - DO NOT STORE OR DISPLAY THIS
# Increased complexity slightly
$randomPassword = -join ((65..90) + (97..122) + (48..57) + (33..47) + (58..64) | Get-Random -Count 20)
$securePassword = ConvertTo-SecureString -String $randomPassword -AsPlainText -Force
$passwordProfile = @{
    Password = $securePassword
    ForceChangePasswordNextSignIn = $true # Set to true even though account is disabled (standard practice)
}

try {
    Update-MgUser -UserId $mgUser.Id -PasswordProfile $passwordProfile -ErrorAction Stop
    Write-Host "[SUCCESS] Password reset for $userUPN. New password is random and was NOT recorded." -ForegroundColor Green
}
catch {
    Write-Warning "[FAILED] Could not reset password for $userUPN."
    Write-Warning "Specific Error: $($_.Exception.Message)"
}

# --- Action 3: Revoke Sign-in Sessions ---
Write-Host "`nSTEP 4: Attempting to revoke all active sessions for $userUPN..." -ForegroundColor Cyan
try {
    # This command immediately invalidates all refresh tokens issued to applications for a user.
    # It also invalidates session cookies in a browser for the user for specific services like OWA/SPO.
    Revoke-MgUserSignInSession -UserId $mgUser.Id -ErrorAction Stop
    Write-Host "[SUCCESS] Initiated sign-out from all active sessions for $userUPN." -ForegroundColor Green
    # Note: Propagation might take a short while across all services.
}
catch {
    # Check for a common 'UserNotFound' error which can sometimes occur transiently or if account state is unusual
    if ($_.Exception.Message -like '*UserNotFound*') {
         Write-Warning "[INFO] Could not revoke sessions, potentially due to account state or replication delay. Sign-in is disabled." -ForegroundColor Yellow
    } else {
        Write-Warning "[FAILED] Could not revoke sign-in sessions for $userUPN."
        Write-Warning "Specific Error: $($_.Exception.Message)"
    }
}

# --- Action 4: Convert Mailbox to Shared ---
Write-Host "`nSTEP 5: Attempting to convert mailbox for $userUPN to Shared..." -ForegroundColor Cyan
try {
    # First, check if a mailbox exists and what type it is using ExchangeOnline cmdlets
    $mailbox = Get-Mailbox -Identity $userUPN -ErrorAction SilentlyContinue # Use SilentlyContinue to handle cases where no mailbox exists

    if ($mailbox) {
         Write-Host "Mailbox found. Current type: $($mailbox.RecipientTypeDetails)." -ForegroundColor Cyan
        if ($mailbox.RecipientTypeDetails -ne "SharedMailbox") {
            # Check for holds before attempting conversion
             if ($mailbox.LitigationHoldEnabled -or $mailbox.InPlaceHolds) {
                 Write-Warning "[BLOCKED] Mailbox cannot be converted because Litigation Hold or In-Place Hold is enabled." -ForegroundColor Yellow
                 Write-Warning "Please remove holds manually according to your organization's policy before conversion."
             } else {
                # Attempt conversion
                Write-Host "Converting mailbox to Shared..."
                Set-Mailbox -Identity $userUPN -Type Shared -ErrorAction Stop
                Write-Host "[SUCCESS] Converted mailbox for $userUPN to Shared." -ForegroundColor Green
                Write-Host "IMPORTANT: You can now remove the license from $userUPN if the shared mailbox is under 50GB." -ForegroundColor Yellow
                Write-Host "Verify shared mailbox access/permissions as needed." -ForegroundColor Yellow
             }
        }
        else {
            Write-Host "[INFO] Mailbox for $userUPN is already a Shared Mailbox. No conversion needed." -ForegroundColor Cyan
        }
    }
    else {
        Write-Warning "[SKIPPED] No mailbox found for $userUPN. Cannot convert."
    }
}
catch {
    Write-Warning "[FAILED] Could not convert mailbox for $userUPN."
    Write-Warning "Specific Error: $($_.Exception.Message)"
    Write-Warning "Check for other potential blockers like specific Retention Policies if holds were not detected." -ForegroundColor Yellow
}
#endregion

#region Disconnect (Optional - Good Practice)
Write-Host "`nOffboarding script actions completed for $userUPN." -ForegroundColor Yellow
# Uncomment the lines below if you want the script to explicitly disconnect sessions
# Write-Host "Disconnecting from Microsoft 365 services..." -ForegroundColor Cyan
# Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
# Disconnect-MgGraph -ErrorAction SilentlyContinue
# Write-Host "Disconnected." -ForegroundColor Green
#endregion

Write-Host "`nScript finished. Please review output for any warnings or errors." -ForegroundColor White
