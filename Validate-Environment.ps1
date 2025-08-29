#Requires -Version 5.1
<#
.SYNOPSIS
    CyberArk Privilege Cloud Environment Validation Script

.DESCRIPTION
    This script validates the environment and prerequisites for running the CyberArk Safe Permission Remapping script.
    It checks for required modules, connectivity, and provides a test of basic API functionality.

.PARAMETER TenantURL
    The CyberArk Privilege Cloud tenant URL to test connectivity

.PARAMETER MappingFile
    Optional path to validate your mapping file format

.PARAMETER TestWebAuth
    Test web-based authentication capabilities (Windows Forms assemblies)

.EXAMPLE
    .\Validate-Environment.ps1 -TenantURL "https://subdomain.cyberark.cloud"
  

.EXAMPLE
    .\Validate-Environment.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.csv" -TestWebAuth
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantURL,
    
    [Parameter(Mandatory = $false)]
    [string]$MappingFile,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestWebAuth
)

function Write-ValidationResult {
    param(
        [string]$Test,
        [bool]$Passed,
        [string]$Message = ""
    )
    
    $status = if ($Passed) { "✅ PASS" } else { "❌ FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "$status - $Test" -ForegroundColor $color
    if ($Message) {
        Write-Host "    $Message" -ForegroundColor Yellow
    }
}

function Test-PowerShellVersion {
    $version = $PSVersionTable.PSVersion
    $passed = $version.Major -ge 5 -and $version.Minor -ge 1
    $message = "Current version: $($version.ToString())"
    if (-not $passed) {
        $message += " (Required: 5.1 or higher)"
    }
    Write-ValidationResult -Test "PowerShell Version" -Passed $passed -Message $message
    return $passed
}

function Test-WebAuthCapabilities {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Web -ErrorAction Stop
        
        # Test if we can create the required objects
        $testForm = New-Object System.Windows.Forms.Form -ErrorAction Stop
        $testBrowser = New-Object System.Windows.Forms.WebBrowser -ErrorAction Stop
        
        $testForm.Dispose()
        $testBrowser.Dispose()
        
        $passed = $true
        $message = "Web authentication components available"
    }
    catch {
        $passed = $false
        $message = "Web authentication not available: $($_.Exception.Message)"
    }
    
    Write-ValidationResult -Test "Web Authentication Support" -Passed $passed -Message $message
    return $passed
}

function Test-ImportExcelModule {
    $module = Get-Module -ListAvailable -Name ImportExcel
    $passed = $null -ne $module
    $message = if ($passed) { 
        "Version: $($module.Version)" 
    } else { 
        "Install with: Install-Module ImportExcel -Force" 
    }
    Write-ValidationResult -Test "ImportExcel Module (for .xlsx files)" -Passed $passed -Message $message
    return $passed
}

function Test-TenantConnectivity {
    param([string]$URL)
    
    try {
        $cleanURL = $URL.TrimEnd('/')
        $testURL = "$cleanURL/PasswordVault/API/accounts"
        
        # Test basic connectivity (this will return 401 but proves the endpoint is reachable)
        $response = Invoke-WebRequest -Uri $testURL -Method GET -ErrorAction Stop
        $passed = $true
        $message = "Tenant is reachable"
    }
    catch [System.Net.WebException] {
        # 401 Unauthorized is expected without authentication
        if ($_.Exception.Response.StatusCode -eq 401) {
            $passed = $true
            $message = "Tenant is reachable (authentication required)"
        } else {
            $passed = $false
            $message = "Connection failed: $($_.Exception.Message)"
        }
    }
    catch {
        $passed = $false
        $message = "Connection failed: $($_.Exception.Message)"
    }
    
    Write-ValidationResult -Test "Tenant Connectivity" -Passed $passed -Message $message
    return $passed
}

function Test-MappingFileFormat {
    param([string]$FilePath)
    
    if (-not $FilePath -or -not (Test-Path $FilePath)) {
        Write-ValidationResult -Test "Mapping File Validation" -Passed $true -Message "No mapping file specified to validate"
        return $true
    }
    
    try {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
        $mappingCount = 0
        
        if ($extension -eq ".csv") {
            $data = Import-Csv -Path $FilePath
            $mappingCount = $data.Count
            $firstRow = $data[0]
            $columns = $firstRow.PSObject.Properties.Count
            
            if ($columns -lt 2) {
                Write-ValidationResult -Test "Mapping File Format" -Passed $false -Message "CSV must have at least 2 columns"
                return $false
            }
        }
        elseif ($extension -eq ".xlsx") {
            if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                Write-ValidationResult -Test "Mapping File Format" -Passed $false -Message "ImportExcel module required for .xlsx files"
                return $false
            }
            
            $data = Import-Excel -Path $FilePath
            $mappingCount = $data.Count
            $firstRow = $data[0]
            $columns = $firstRow.PSObject.Properties.Count
            
            if ($columns -lt 2) {
                Write-ValidationResult -Test "Mapping File Format" -Passed $false -Message "Excel file must have at least 2 columns"
                return $false
            }
        }
        else {
            Write-ValidationResult -Test "Mapping File Format" -Passed $false -Message "Unsupported file format. Use .csv or .xlsx"
            return $false
        }
        
        Write-ValidationResult -Test "Mapping File Format" -Passed $true -Message "Valid format with $mappingCount mappings"
        
        # Show sample mappings
        if ($mappingCount -gt 0) {
            Write-Host "`nSample mappings from your file:" -ForegroundColor Cyan
            $sampleCount = [Math]::Min(3, $mappingCount)
            for ($i = 0; $i -lt $sampleCount; $i++) {
                $row = $data[$i]
                $oldGroup = $row.PSObject.Properties[0].Value
                $newGroup = $row.PSObject.Properties[1].Value
                Write-Host "  $oldGroup → $newGroup" -ForegroundColor White
            }
            if ($mappingCount -gt 3) {
                Write-Host "  ... and $($mappingCount - 3) more" -ForegroundColor Gray
            }
        }
        
        return $true
    }
    catch {
        Write-ValidationResult -Test "Mapping File Format" -Passed $false -Message "Error reading file: $($_.Exception.Message)"
        return $false
    }
}

function Show-NextSteps {
    param([bool[]]$Results)
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "VALIDATION SUMMARY" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    $passedCount = ($Results | Where-Object { $_ }).Count
    $totalCount = $Results.Count
    
    if ($passedCount -eq $totalCount) {
        Write-Host "✅ All validations passed! Your environment is ready." -ForegroundColor Green
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "1. Run a dry run first:" -ForegroundColor White
        Write-Host "   .\CyberArk-SafePermissionRemap.ps1 -TenantURL `"$TenantURL`" -MappingFile `"YourMapping.csv`" -DryRun" -ForegroundColor Gray
        Write-Host "2. Review the dry run report" -ForegroundColor White
        Write-Host "3. Execute the actual remapping" -ForegroundColor White
    }
    else {
        Write-Host "❌ $($totalCount - $passedCount) validation(s) failed. Please address the issues above." -ForegroundColor Red
        Write-Host "`nCommon fixes:" -ForegroundColor Yellow
        Write-Host "- Install missing modules: Install-Module ImportExcel" -ForegroundColor White
        Write-Host "- Verify tenant URL format: https://subdomain.cyberark.cloud" -ForegroundColor White
        Write-Host "- Check mapping file format and content" -ForegroundColor White
    }
}

# Main validation execution
Write-Host "CyberArk Privilege Cloud Environment Validation" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host "Tenant URL: $TenantURL" -ForegroundColor White
if ($MappingFile) {
    Write-Host "Mapping File: $MappingFile" -ForegroundColor White
}
Write-Host ""

# Run all validations
$results = @()
$results += Test-PowerShellVersion
$results += Test-ImportExcelModule
if ($TestWebAuth) {
    $results += Test-WebAuthCapabilities
}
$results += Test-TenantConnectivity -URL $TenantURL
$results += Test-MappingFileFormat -FilePath $MappingFile

# Show summary and next steps
Show-NextSteps -Results $results

Write-Host "`nFor more information, see the README.md file." -ForegroundColor Gray
