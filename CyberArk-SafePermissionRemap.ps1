#Requires -Version 5.1
<#
.SYNOPSIS
  [CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantURL,
    
    [Parameter(Mandatory = $true)]
    [string]$MappingFile,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [switch]$DeleteOldPermissions,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".",
    
    [Parameter(Mandatory = $false)]
    [switch]$UseWebAuth,
    
    [Parameter(Mandatory = $false)]
    [switch]$UseCredentials,
    
    [Parameter(Mandatory = $false)]
    [switch]$IgnoreUnmappedGroups
)ege Cloud Safe Permission Remapping Script

.DESCRIPTION
    This script allows CyberArk Privilege Cloud Administrators to remap permissions on safes from one group to another.
    The mapping is handled by a lookup from an external Excel or CSV file with two columns:
    - Column 1: Existing group names
    - Column 2: New group names

.PARAMETER TenantURL
    The CyberArk Privilege Cloud tenant URL (e.g., https://subdomain.cyberark.cloud)

.PARAMETER MappingFile
    Path to the Excel (.xlsx) or CSV file containing the group mapping

.PARAMETER DryRun
    When specified, performs a dry run and outputs proposed changes without making actual modifications

.PARAMETER DeleteOldPermissions
    When specified, removes the old group permissions after adding new ones

.PARAMETER OutputPath
    Directory path for output files (defaults to current directory)

.PARAMETER UseWebAuth
    When specified, uses web-based authentication with MFA support via SAML/OIDC instead of username/password

.PARAMETER UseCredentials
    When specified, forces the use of username/password authentication (legacy mode)

.PARAMETER IgnoreUnmappedGroups
    When specified, ignores groups found in safes that don't have a mapping in the CSV/Excel file instead of prompting for action

.EXAMPLE
    .\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.csv" -UseWebAuth -DryRun

.EXAMPLE
    .\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.xlsx" -UseWebAuth -DeleteOldPermissions

.EXAMPLE
    .\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.csv" -UseWebAuth -IgnoreUnmappedGroups

.NOTES
    Author: CyberArk Privilege Cloud Administrator
    Version: 1.0
    Requires: PowerShell 5.1+, ImportExcel module (for Excel files)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantURL,
    
    [Parameter(Mandatory = $true)]
    [string]$MappingFile,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [switch]$DeleteOldPermissions,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "."
)

# Global variables
$script:AuthToken = $null
$script:BaseURL = $TenantURL.TrimEnd('/')
$script:Headers = @{'Content-Type' = 'application/json'}
$script:LogFile = Join-Path $OutputPath "SafeRemapping_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:ChangeLog = @()

#region Helper Functions

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $script:LogFile -Value $logEntry
}

function Handle-UnmappedGroup {
    param(
        [string]$GroupName,
        [string]$SafeName,
        [hashtable]$GroupMapping
    )
    
    Write-Host "`n" + "="*60 -ForegroundColor Yellow
    Write-Host "UNMAPPED GROUP FOUND" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Yellow
    Write-Host "Safe: $SafeName" -ForegroundColor White
    Write-Host "Group: $GroupName" -ForegroundColor Cyan
    Write-Host "This group was not found in your mapping file." -ForegroundColor Red
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "1. Specify a new group name for this mapping" -ForegroundColor White
    Write-Host "2. Ignore this group (no changes will be made)" -ForegroundColor White
    Write-Host "3. Ignore all remaining unmapped groups" -ForegroundColor White
    Write-Host "4. Cancel the operation" -ForegroundColor White
    Write-Host ""
    
    do {
        $choice = Read-Host "Enter your choice (1-4)"
        
        switch ($choice) {
            "1" {
                $newGroupName = Read-Host "Enter the new group name for '$GroupName'"
                if ($newGroupName.Trim()) {
                    # Add to the mapping for future references
                    $GroupMapping[$GroupName] = $newGroupName.Trim()
                    Write-Host "Added mapping: $GroupName -> $newGroupName" -ForegroundColor Green
                    return @{Action = "Map"; NewGroup = $newGroupName.Trim()}
                } else {
                    Write-Host "Invalid group name. Please try again." -ForegroundColor Red
                    continue
                }
            }
            "2" {
                Write-Host "Ignoring group '$GroupName'" -ForegroundColor Yellow
                return @{Action = "Ignore"}
            }
            "3" {
                Write-Host "Will ignore all remaining unmapped groups" -ForegroundColor Yellow
                return @{Action = "IgnoreAll"}
            }
            "4" {
                Write-Host "Cancelling operation..." -ForegroundColor Red
                return @{Action = "Cancel"}
            }
            default {
                Write-Host "Invalid choice. Please enter 1, 2, 3, or 4." -ForegroundColor Red
            }
        }
    } while ($true)
}

function Generate-UnmappedGroupsReport {
    param([array]$UnmappedGroups, [string]$OutputPath)
    
    if ($UnmappedGroups.Count -eq 0) {
        return $null
    }
    
    $reportFile = Join-Path $OutputPath "UnmappedGroups_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    $reportData = @()
    foreach ($group in $UnmappedGroups) {
        $reportData += [PSCustomObject]@{
            SafeName = $group.SafeName
            GroupName = $group.GroupName
            MemberType = $group.MemberType
            Permissions = ($group.Permissions | ConvertTo-Json -Compress)
        }
    }
    
    $reportData | Export-Csv -Path $reportFile -NoTypeInformation
    Write-Log "Unmapped groups report saved to: $reportFile"
    return $reportFile
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check if mapping file exists
    if (-not (Test-Path $MappingFile)) {
        throw "Mapping file not found: $MappingFile"
    }
    
    # Check file extension and required modules
    $fileExtension = [System.IO.Path]::GetExtension($MappingFile).ToLower()
    if ($fileExtension -eq ".xlsx") {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            throw "ImportExcel module is required for Excel files. Install with: Install-Module ImportExcel"
        }
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Prerequisites check completed successfully"
}

function Get-WebAuthToken {
    Write-Log "Starting web-based authentication with MFA support..."
    
    try {
        # Add required assemblies for web browser control
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Web
        
        # Generate PKCE parameters for OAuth2
        $codeVerifier = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([System.Guid]::NewGuid().ToString())).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $codeChallenge = [System.Convert]::ToBase64String([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($codeVerifier))).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        
        # OAuth2 parameters
        $clientId = "PasswordVault"  # Default CyberArk client ID
        $redirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"
        $state = [System.Guid]::NewGuid().ToString()
        
        # Construct authorization URL
        $authUrl = "$script:BaseURL/PasswordVault/API/auth/oidc/login" +
                   "?client_id=$clientId" +
                   "&response_type=code" +
                   "&redirect_uri=$([System.Web.HttpUtility]::UrlEncode($redirectUri))" +
                   "&state=$state" +
                   "&code_challenge=$codeChallenge" +
                   "&code_challenge_method=S256"
        
        Write-Log "Opening web browser for authentication..."
        
        # Create and configure the web browser form
        $form = New-Object System.Windows.Forms.Form
        $form.Text = "CyberArk Privilege Cloud Authentication"
        $form.Size = New-Object System.Drawing.Size(800, 600)
        $form.StartPosition = "CenterScreen"
        $form.WindowState = "Normal"
        
        $webBrowser = New-Object System.Windows.Forms.WebBrowser
        $webBrowser.Dock = "Fill"
        $webBrowser.ScriptErrorsSuppressed = $true
        
        $authCode = $null
        $authError = $null
        
        # Handle navigation events to capture the authorization code
        $webBrowser.Add_DocumentCompleted({
            param($sender, $e)
            
            $currentUrl = $sender.Url.ToString()
            Write-Log "Browser navigated to: $($currentUrl.Substring(0, [Math]::Min(100, $currentUrl.Length)))..."
            
            # Check if we've been redirected to the callback URL with authorization code
            if ($currentUrl.StartsWith($redirectUri)) {
                $uri = [System.Uri]$currentUrl
                $queryParams = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
                
                if ($queryParams["code"]) {
                    $script:authCode = $queryParams["code"]
                    $receivedState = $queryParams["state"]
                    
                    if ($receivedState -eq $state) {
                        Write-Log "Authorization code received successfully"
                        $form.Close()
                    } else {
                        $script:authError = "State parameter mismatch - possible security issue"
                        $form.Close()
                    }
                } elseif ($queryParams["error"]) {
                    $script:authError = "Authentication error: $($queryParams['error']) - $($queryParams['error_description'])"
                    $form.Close()
                }
            }
        })
        
        # Handle form closing
        $form.Add_FormClosed({
            if (-not $script:authCode -and -not $script:authError) {
                $script:authError = "Authentication was cancelled by user"
            }
        })
        
        $form.Controls.Add($webBrowser)
        $webBrowser.Navigate($authUrl)
        
        # Show the form and wait for user interaction
        $form.ShowDialog() | Out-Null
        
        if ($authError) {
            throw $authError
        }
        
        if (-not $authCode) {
            throw "Failed to obtain authorization code"
        }
        
        # Exchange authorization code for access token
        Write-Log "Exchanging authorization code for access token..."
        
        $tokenBody = @{
            grant_type = "authorization_code"
            client_id = $clientId
            code = $authCode
            redirect_uri = $redirectUri
            code_verifier = $codeVerifier
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "$script:BaseURL/PasswordVault/API/auth/oidc/token" -Method POST -Body $tokenBody -Headers @{'Content-Type' = 'application/x-www-form-urlencoded'}
        
        if ($tokenResponse.access_token) {
            $script:AuthToken = $tokenResponse.access_token
            $script:Headers['Authorization'] = "Bearer $($tokenResponse.access_token)"
            Write-Log "Web authentication completed successfully"
            return $true
        } else {
            throw "Failed to obtain access token from authorization code"
        }
    }
    catch {
        Write-Log "Web authentication failed: $($_.Exception.Message)" -Level "ERROR"
        throw "Web authentication failed: $($_.Exception.Message)"
    }
}

function Get-AuthToken {
    if ($UseWebAuth) {
        return Get-WebAuthToken
    } else {
        return Get-CredentialAuthToken
    }
}

function Get-CredentialAuthToken {
function Get-CredentialAuthToken {
    Write-Log "Authenticating to CyberArk Privilege Cloud using username/password..."
    
    # Get credentials
    $credential = Get-Credential -Message "Enter your CyberArk Privilege Cloud credentials"
    
    $authBody = @{
        username = $credential.UserName
        password = $credential.GetNetworkCredential().Password
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$script:BaseURL/PasswordVault/API/auth/cyberark/Logon" -Method POST -Body $authBody -Headers $script:Headers
        $script:AuthToken = $response
        $script:Headers['Authorization'] = $response
        Write-Log "Username/password authentication successful"
    }
    catch {
        throw "Username/password authentication failed: $($_.Exception.Message)"
    }
}

function Test-AuthenticationParameters {
    # Validate authentication method parameters
    if ($UseWebAuth -and $UseCredentials) {
        throw "Cannot specify both -UseWebAuth and -UseCredentials. Please choose one authentication method."
    }
    
    # Default to web auth if neither is specified
    if (-not $UseWebAuth -and -not $UseCredentials) {
        Write-Log "No authentication method specified. Defaulting to web-based authentication with MFA support." -Level "INFO"
        $script:UseWebAuth = $true
    }
    
    # Check for Windows Forms assembly availability for web auth
    if ($UseWebAuth) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            Add-Type -AssemblyName System.Web -ErrorAction Stop
        }
        catch {
            Write-Log "Windows Forms assemblies not available. Falling back to credential authentication." -Level "WARNING"
            $script:UseCredentials = $true
            $script:UseWebAuth = $false
        }
    }
}
}

function Get-GroupMapping {
    Write-Log "Loading group mapping from file: $MappingFile"
    
    $fileExtension = [System.IO.Path]::GetExtension($MappingFile).ToLower()
    $mapping = @{}
    
    try {
        if ($fileExtension -eq ".csv") {
            $data = Import-Csv -Path $MappingFile
            foreach ($row in $data) {
                $oldGroup = $row.PSObject.Properties[0].Value
                $newGroup = $row.PSObject.Properties[1].Value
                if ($oldGroup -and $newGroup) {
                    $mapping[$oldGroup] = $newGroup
                }
            }
        }
        elseif ($fileExtension -eq ".xlsx") {
            $data = Import-Excel -Path $MappingFile
            foreach ($row in $data) {
                $oldGroup = $row.PSObject.Properties[0].Value
                $newGroup = $row.PSObject.Properties[1].Value
                if ($oldGroup -and $newGroup) {
                    $mapping[$oldGroup] = $newGroup
                }
            }
        }
        else {
            throw "Unsupported file format. Please use .csv or .xlsx"
        }
        
        Write-Log "Loaded $($mapping.Count) group mappings"
        return $mapping
    }
    catch {
        throw "Failed to load mapping file: $($_.Exception.Message)"
    }
}

function Get-AllSafes {
    Write-Log "Retrieving all safes from Privilege Cloud..."
    
    try {
        $safes = @()
        $offset = 0
        $limit = 1000
        
        do {
            $uri = "$script:BaseURL/PasswordVault/API/safes?offset=$offset&limit=$limit"
            $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $script:Headers
            $safes += $response.safes
            $offset += $limit
        } while ($response.safes.Count -eq $limit)
        
        Write-Log "Retrieved $($safes.Count) safes"
        return $safes
    }
    catch {
        throw "Failed to retrieve safes: $($_.Exception.Message)"
    }
}

function Get-SafeMembers {
    param([string]$SafeName)
    
    try {
        $uri = "$script:BaseURL/PasswordVault/API/safes/$SafeName/members"
        $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $script:Headers
        return $response.members
    }
    catch {
        Write-Log "Failed to retrieve members for safe '$SafeName': $($_.Exception.Message)" -Level "WARNING"
        return @()
    }
}

function Add-SafeMember {
    param(
        [string]$SafeName,
        [string]$MemberName,
        [hashtable]$Permissions
    )
    
    $memberBody = @{
        memberName = $MemberName
        searchIn = "Vault"
        membershipExpirationDate = $null
        permissions = $Permissions
    } | ConvertTo-Json
    
    try {
        $uri = "$script:BaseURL/PasswordVault/API/safes/$SafeName/members"
        Invoke-RestMethod -Uri $uri -Method POST -Body $memberBody -Headers $script:Headers
        return $true
    }
    catch {
        Write-Log "Failed to add member '$MemberName' to safe '$SafeName': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Remove-SafeMember {
    param(
        [string]$SafeName,
        [string]$MemberName
    )
    
    try {
        $uri = "$script:BaseURL/PasswordVault/API/safes/$SafeName/members/$MemberName"
        Invoke-RestMethod -Uri $uri -Method DELETE -Headers $script:Headers
        return $true
    }
    catch {
        Write-Log "Failed to remove member '$MemberName' from safe '$SafeName': $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Generate-DryRunReport {
    param(
        [array]$ProposedChanges,
        [array]$UnmappedGroups = @()
    )
    
    $dryRunFile = Join-Path $OutputPath "DryRun_SafeRemapping_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    $reportData = @()
    foreach ($change in $ProposedChanges) {
        $reportData += [PSCustomObject]@{
            SafeName = $change.SafeName
            Action = $change.Action
            OldGroup = $change.OldGroup
            NewGroup = $change.NewGroup
            Permissions = ($change.Permissions | ConvertTo-Json -Compress)
            Status = "Mapped"
        }
    }
    
    # Add unmapped groups to the dry run report
    foreach ($unmapped in $UnmappedGroups) {
        $reportData += [PSCustomObject]@{
            SafeName = $unmapped.SafeName
            Action = "UNMAPPED"
            OldGroup = $unmapped.GroupName
            NewGroup = "REQUIRES_MAPPING"
            Permissions = ($unmapped.Permissions | ConvertTo-Json -Compress)
            Status = "Unmapped - Requires Action"
        }
    }
    
    $reportData | Export-Csv -Path $dryRunFile -NoTypeInformation
    Write-Log "Dry run report saved to: $dryRunFile"
    return $dryRunFile
}

function Generate-ChangeReport {
    $changeFile = Join-Path $OutputPath "Changes_SafeRemapping_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    
    $script:ChangeLog | Export-Csv -Path $changeFile -NoTypeInformation
    Write-Log "Change report saved to: $changeFile"
    return $changeFile
}

#endregion

#region Main Logic

function Start-SafeRemapping {
    try {
        Write-Log "Starting CyberArk Safe Permission Remapping Process"
        
        # Validate authentication parameters
        Test-AuthenticationParameters
        
        # Check prerequisites
        Test-Prerequisites
        
        # Authenticate
        Get-AuthToken
        
        # Load group mapping
        $groupMapping = Get-GroupMapping
        
        # Get all safes
        $safes = Get-AllSafes
        
        # Analyze safes and prepare changes
        Write-Log "Analyzing safes and preparing changes..."
        $proposedChanges = @()
        $unmappedGroups = @()
        $processedSafes = 0
        $ignoreAllUnmapped = $IgnoreUnmappedGroups
        
        foreach ($safe in $safes) {
            $processedSafes++
            Write-Progress -Activity "Analyzing Safes" -Status "Processing $($safe.safeName)" -PercentComplete (($processedSafes / $safes.Count) * 100)
            
            $members = Get-SafeMembers -SafeName $safe.safeName
            
            foreach ($member in $members) {
                if ($member.memberType -eq "Group") {
                    if ($groupMapping.ContainsKey($member.memberName)) {
                        # Group has a mapping - process normally
                        $newGroupName = $groupMapping[$member.memberName]
                        
                        # Add new group
                        $proposedChanges += [PSCustomObject]@{
                            SafeName = $safe.safeName
                            Action = "Add"
                            OldGroup = $member.memberName
                            NewGroup = $newGroupName
                            Permissions = $member.permissions
                        }
                        
                        # Remove old group (if specified)
                        if ($DeleteOldPermissions) {
                            $proposedChanges += [PSCustomObject]@{
                                SafeName = $safe.safeName
                                Action = "Remove"
                                OldGroup = $member.memberName
                                NewGroup = ""
                                Permissions = $member.permissions
                            }
                        }
                    } else {
                        # Group doesn't have a mapping - handle unmapped group
                        $unmappedGroups += [PSCustomObject]@{
                            SafeName = $safe.safeName
                            GroupName = $member.memberName
                            MemberType = $member.memberType
                            Permissions = $member.permissions
                        }
                        
                        # If not ignoring all unmapped groups and not in dry run mode, prompt user
                        if (-not $ignoreAllUnmapped -and -not $DryRun) {
                            $result = Handle-UnmappedGroup -GroupName $member.memberName -SafeName $safe.safeName -GroupMapping $groupMapping
                            
                            switch ($result.Action) {
                                "Map" {
                                    # User provided a new mapping
                                    $newGroupName = $result.NewGroup
                                    
                                    # Add new group
                                    $proposedChanges += [PSCustomObject]@{
                                        SafeName = $safe.safeName
                                        Action = "Add"
                                        OldGroup = $member.memberName
                                        NewGroup = $newGroupName
                                        Permissions = $member.permissions
                                    }
                                    
                                    # Remove old group (if specified)
                                    if ($DeleteOldPermissions) {
                                        $proposedChanges += [PSCustomObject]@{
                                            SafeName = $safe.safeName
                                            Action = "Remove"
                                            OldGroup = $member.memberName
                                            NewGroup = ""
                                            Permissions = $member.permissions
                                        }
                                    }
                                }
                                "Ignore" {
                                    Write-Log "Ignoring unmapped group '$($member.memberName)' in safe '$($safe.safeName)'" -Level "WARNING"
                                }
                                "IgnoreAll" {
                                    $ignoreAllUnmapped = $true
                                    Write-Log "Will ignore all remaining unmapped groups" -Level "WARNING"
                                }
                                "Cancel" {
                                    throw "Operation cancelled by user due to unmapped group"
                                }
                            }
                        } elseif (-not $ignoreAllUnmapped) {
                            Write-Log "Found unmapped group '$($member.memberName)' in safe '$($safe.safeName)' - will be reported" -Level "WARNING"
                        }
                    }
                }
            }
        }
        
        Write-Progress -Activity "Analyzing Safes" -Completed
        Write-Log "Analysis complete. Found $($proposedChanges.Count) proposed changes across $($safes.Count) safes"
        
        # Report unmapped groups
        if ($unmappedGroups.Count -gt 0) {
            Write-Log "Found $($unmappedGroups.Count) unmapped groups across safes" -Level "WARNING"
            $unmappedGroupsReport = Generate-UnmappedGroupsReport -UnmappedGroups $unmappedGroups -OutputPath $OutputPath
            
            if (-not $DryRun -and -not $ignoreAllUnmapped) {
                Write-Host "`nUnmapped Groups Summary:" -ForegroundColor Yellow
                $groupsByName = $unmappedGroups | Group-Object GroupName
                foreach ($group in $groupsByName) {
                    Write-Host "- $($group.Name): Found in $($group.Count) safe(s)" -ForegroundColor Cyan
                }
                Write-Host "Unmapped groups report: $unmappedGroupsReport" -ForegroundColor Gray
            }
        }
        
        # Handle dry run
        if ($DryRun) {
            Write-Log "Performing dry run..."
            $dryRunFile = Generate-DryRunReport -ProposedChanges $proposedChanges -UnmappedGroups $unmappedGroups
            Write-Log "Dry run completed. Review the report at: $dryRunFile"
            
            if ($unmappedGroups.Count -gt 0) {
                Write-Host "`nDry Run Note:" -ForegroundColor Yellow
                Write-Host "Found $($unmappedGroups.Count) unmapped groups that would require attention during actual execution." -ForegroundColor Yellow
                Write-Host "Review the unmapped groups report: $unmappedGroupsReport" -ForegroundColor Gray
            }
            
            return
        }
        
        # Confirm changes with user
        if ($proposedChanges.Count -eq 0) {
            Write-Log "No changes required based on the group mapping provided"
            return
        }
        
        Write-Host "`nProposed Changes Summary:" -ForegroundColor Yellow
        Write-Host "- Add operations: $(($proposedChanges | Where-Object {$_.Action -eq 'Add'}).Count)" -ForegroundColor Green
        Write-Host "- Remove operations: $(($proposedChanges | Where-Object {$_.Action -eq 'Remove'}).Count)" -ForegroundColor Red
        Write-Host "- Total safes affected: $(($proposedChanges | Select-Object SafeName -Unique).Count)" -ForegroundColor Cyan
        
        $confirmation = Read-Host "`nDo you want to proceed with these changes? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-Log "Operation cancelled by user"
            return
        }
        
        # Execute changes
        Write-Log "Executing changes..."
        $successCount = 0
        $errorCount = 0
        $changeCounter = 0
        
        foreach ($change in $proposedChanges) {
            $changeCounter++
            Write-Progress -Activity "Executing Changes" -Status "Processing change $changeCounter of $($proposedChanges.Count)" -PercentComplete (($changeCounter / $proposedChanges.Count) * 100)
            
            $success = $false
            
            if ($change.Action -eq "Add") {
                $success = Add-SafeMember -SafeName $change.SafeName -MemberName $change.NewGroup -Permissions $change.Permissions
                $actionDescription = "Added group '$($change.NewGroup)' to safe '$($change.SafeName)'"
            }
            elseif ($change.Action -eq "Remove") {
                $success = Remove-SafeMember -SafeName $change.SafeName -MemberName $change.OldGroup
                $actionDescription = "Removed group '$($change.OldGroup)' from safe '$($change.SafeName)'"
            }
            
            # Log the change
            $script:ChangeLog += [PSCustomObject]@{
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                SafeName = $change.SafeName
                Action = $change.Action
                OldGroup = $change.OldGroup
                NewGroup = $change.NewGroup
                Success = $success
                Description = $actionDescription
            }
            
            if ($success) {
                $successCount++
                Write-Log $actionDescription
            } else {
                $errorCount++
            }
            
            # Small delay to avoid overwhelming the API
            Start-Sleep -Milliseconds 100
        }
        
        Write-Progress -Activity "Executing Changes" -Completed
        
        # Generate final report
        $changeReportFile = Generate-ChangeReport
        
        Write-Log "Remapping process completed"
        Write-Log "Successful operations: $successCount"
        Write-Log "Failed operations: $errorCount"
        Write-Log "Change report saved to: $changeReportFile"
        
    }
    catch {
        Write-Log "Critical error: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
    finally {
        # Cleanup
        if ($script:AuthToken) {
            try {
                if ($UseWebAuth) {
                    # For OAuth2/OIDC tokens, we typically don't need to explicitly revoke
                    # as they have expiration times, but we can clear our local reference
                    Write-Log "Clearing OAuth2 token"
                } else {
                    # For traditional CyberArk authentication, perform logoff
                    Invoke-RestMethod -Uri "$script:BaseURL/PasswordVault/API/auth/Logoff" -Method POST -Headers $script:Headers
                    Write-Log "Logged off from CyberArk Privilege Cloud"
                }
            }
            catch {
                Write-Log "Failed to complete logout process: $($_.Exception.Message)" -Level "WARNING"
            }
            finally {
                $script:AuthToken = $null
                $script:Headers.Remove('Authorization')
            }
        }
    }
}

#endregion

# Execute the main function
try {
    Start-SafeRemapping
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
}
