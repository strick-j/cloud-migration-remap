# CyberArk Privilege Cloud Safe Permission Remapping Tool

This repository contains a PowerShell script that allows CyberArk Privilege Cloud Administrators to remap permissions on safes from one group to another using an external mapping file.

## Features

- **Multiple Authentication Methods**: Support for both web-based authentication with MFA (SAML/OIDC) and traditional username/password
- **Unmapped Group Detection**: Identifies and handles groups in safes that don't have mappings in your file
- **Interactive Group Mapping**: Prompts users to specify mappings for unmapped groups or ignore them
- **Bulk Safe Permission Remapping**: Automatically remap group permissions across all safes in your Privilege Cloud environment
- **Excel/CSV Support**: Use either Excel (.xlsx) or CSV files for group mapping definitions
- **Dry Run Mode**: Preview changes before execution with detailed reporting
- **Comprehensive Logging**: Detailed logging and change tracking for audit purposes
- **Safe Permission Preservation**: Maintains existing permission levels when remapping groups
- **Optional Cleanup**: Option to remove old group permissions after adding new ones
- **Progress Tracking**: Real-time progress indicators for long-running operations

## Prerequisites

- PowerShell 5.1 or later
- CyberArk Privilege Cloud tenant access with administrative privileges
- For Excel files: `ImportExcel` PowerShell module (`Install-Module ImportExcel`)

## Quick Start

1. **Prepare your mapping file** (CSV or Excel format):
   ```csv
   OldGroupName,NewGroupName
   DOMAIN\OldGroup1,DOMAIN\NewGroup1
   DOMAIN\OldGroup2,DOMAIN\NewGroup2
   ```

2. **Run a dry run first** with web authentication (recommended):
   ```powershell
   .\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.csv" -UseWebAuth -DryRun
   ```

3. **Execute the remapping** with your preferred authentication method:
   ```powershell
   # With web authentication (supports MFA)
   .\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.csv" -UseWebAuth
   
   # With traditional credentials
   .\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://subdomain.cyberark.cloud" -MappingFile "GroupMapping.csv" -UseCredentials
   ```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `TenantURL` | Yes | Your CyberArk Privilege Cloud tenant URL |
| `MappingFile` | Yes | Path to the Excel (.xlsx) or CSV file containing group mappings |
| `UseWebAuth` | No | Use web-based authentication with MFA support via SAML/OIDC |
| `UseCredentials` | No | Use traditional username/password authentication |
| `DryRun` | No | Performs a dry run without making changes |
| `DeleteOldPermissions` | No | Removes old group permissions after adding new ones |
| `IgnoreUnmappedGroups` | No | Silently ignores groups not found in the mapping file |
| `OutputPath` | No | Directory for output files (defaults to current directory) |

## Authentication Methods

### Web-Based Authentication (Recommended)
The script supports modern web-based authentication with MFA via SAML/OIDC:
- Opens a web browser window for secure authentication
- Supports Multi-Factor Authentication (MFA)
- Works with SAML and OIDC identity providers
- Uses OAuth2 with PKCE for enhanced security
- Automatically handles token management

### Traditional Credentials
For environments that require username/password authentication:
- Prompts for CyberArk credentials
- Uses traditional CyberArk authentication API
- Suitable for basic authentication scenarios

## Mapping File Format

### CSV Format
```csv
OldGroupName,NewGroupName
DOMAIN\LegacyAdmins,DOMAIN\ModernAdmins
CORP\DevTeamOld,CORP\DevTeamNew
```

### Excel Format
- Column A: Old Group Names
- Column B: New Group Names
- No headers required (first row will be treated as data)

## Script Workflow

1. **Authentication Method Selection**: Choose between web-based (with MFA) or credential-based authentication
2. **Authentication**: Authenticate using selected method (web browser popup or credential prompt)
3. **Safe Enumeration**: Retrieves all safes and their current group memberships
4. **Mapping Analysis**: Identifies groups that need remapping based on your mapping file
5. **Unmapped Group Handling**: Detects groups without mappings and prompts for action (unless using `-IgnoreUnmappedGroups`)
6. **Change Planning**: Generates a list of proposed changes
7. **Dry Run (Optional)**: Outputs proposed changes and unmapped groups to CSV files for review
8. **User Confirmation**: Requests approval before making changes
9. **Execution**: Adds new group permissions to safes
10. **Cleanup (Optional)**: Removes old group permissions if specified
11. **Reporting**: Generates detailed change logs and reports

## Output Files

The script generates several output files in the specified output directory:

- **Log File**: `SafeRemapping_YYYYMMDD_HHMMSS.log` - Detailed execution log
- **Dry Run Report**: `DryRun_SafeRemapping_YYYYMMDD_HHMMSS.csv` - Preview of proposed changes and unmapped groups
- **Unmapped Groups Report**: `UnmappedGroups_YYYYMMDD_HHMMSS.csv` - Details of groups found without mappings
- **Change Report**: `Changes_SafeRemapping_YYYYMMDD_HHMMSS.csv` - Record of all changes made

## Examples

### Web authentication with dry run
```powershell
.\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://mycompany.cyberark.cloud" -MappingFile "migration-mapping.csv" -UseWebAuth -DryRun
```

### Execute remapping with Excel file, web auth, and cleanup old permissions
```powershell
.\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://mycompany.cyberark.cloud" -MappingFile "GroupMapping.xlsx" -UseWebAuth -DeleteOldPermissions -OutputPath "C:\Reports"
```

### Traditional credentials with custom output location
```powershell
.\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://mycompany.cyberark.cloud" -MappingFile "mapping.csv" -UseCredentials -DryRun -OutputPath "C:\MigrationReports"
```

### Handle unmapped groups automatically
```powershell
.\CyberArk-SafePermissionRemap.ps1 -TenantURL "https://mycompany.cyberark.cloud" -MappingFile "GroupMapping.csv" -UseWebAuth -IgnoreUnmappedGroups -DryRun
```

### Test web authentication capabilities
```powershell
.\Validate-Environment.ps1 -TenantURL "https://mycompany.cyberark.cloud" -TestWebAuth
```

## Handling Unmapped Groups

When the script encounters groups in safes that don't have corresponding entries in your mapping file, it provides several options:

### Interactive Mode (Default)
During execution, you'll be prompted with options for each unmapped group:
1. **Specify a new group name** - Enter a replacement group name on-the-fly
2. **Ignore this group** - Skip this specific group (no changes made)
3. **Ignore all remaining unmapped groups** - Skip all subsequent unmapped groups
4. **Cancel the operation** - Stop the entire process

### Automatic Mode
Use the `-IgnoreUnmappedGroups` parameter to silently skip all unmapped groups without prompting.

### Dry Run Benefits
Running with `-DryRun` first will:
- Generate a report showing all unmapped groups
- Allow you to update your mapping file before actual execution
- Prevent interactive prompts during the analysis phase

## Best Practices

1. **Use web authentication when possible** for enhanced security and MFA support
2. **Always run a dry run first** to review proposed changes
3. **Test with a small subset** of groups in a development environment
4. **Backup your current configuration** before making changes
5. **Review the mapping file carefully** for accuracy
6. **Monitor the execution logs** for any errors or warnings
7. **Keep the change reports** for audit and compliance purposes

## Error Handling

The script includes comprehensive error handling:
- Authentication failures are clearly reported
- API errors are logged with detailed messages
- Failed operations are tracked separately from successful ones
- Script continues processing even if individual operations fail

## Security Considerations

- Credentials are prompted securely and not stored in the script
- Authentication tokens are properly cleaned up after execution
- All operations are logged for audit trails
- The script follows the principle of least privilege

## Troubleshooting

### Common Issues

1. **Authentication Fails**: 
   - For web auth: Check if Windows Forms assemblies are available
   - For credentials: Verify your credentials and tenant URL
   - Try the alternative authentication method
2. **Web Browser Issues**: If web auth fails, use `-UseCredentials` parameter
3. **ImportExcel Module Missing**: Install with `Install-Module ImportExcel`
4. **Permission Denied**: Ensure your account has sufficient privileges in Privilege Cloud
5. **Mapping File Issues**: Verify file format and that all group names are correct

### Support

For issues or questions:
1. Check the execution logs for detailed error messages
2. Verify your mapping file format matches the expected structure
3. Test with a smaller mapping file first
4. Ensure all prerequisites are met

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
This repository allows end users to remap safe permissions to different directory sources after a cloud migration.
