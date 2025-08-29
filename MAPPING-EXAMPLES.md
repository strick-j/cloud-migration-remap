# Group Mapping File Examples

This document provides examples of the group mapping file formats supported by the CyberArk Safe Permission Remapping script.

## CSV Format Example

### File: sample-group-mapping.csv
```csv
OldGroupName,NewGroupName
DOMAIN\OldSecurityGroup1,DOMAIN\NewSecurityGroup1
DOMAIN\OldSecurityGroup2,DOMAIN\NewSecurityGroup2
LEGACY_ADMINS,CLOUD_ADMINS
DEV_TEAM_OLD,DEV_TEAM_NEW
QA_TEAM_LEGACY,QA_TEAM_MODERN
CORP\Finance_Old,CORP\Finance_New
MYDOMAIN\IT_Support_Legacy,MYDOMAIN\IT_Support_Modern
```

## Excel Format Requirements

### Sheet Structure
- **Column A**: Old Group Names (existing groups to be replaced)
- **Column B**: New Group Names (new groups to be added)
- **No headers required** (first row is treated as data)
- **Single worksheet** (script reads from the first worksheet)

### Example Excel Content:
| A (Old Group) | B (New Group) |
|---------------|---------------|
| DOMAIN\OldSecurityGroup1 | DOMAIN\NewSecurityGroup1 |
| DOMAIN\OldSecurityGroup2 | DOMAIN\NewSecurityGroup2 |
| LEGACY_ADMINS | CLOUD_ADMINS |
| DEV_TEAM_OLD | DEV_TEAM_NEW |

## Group Name Formats

The script supports various group name formats commonly used in CyberArk:

### Domain Groups
- `DOMAIN\GroupName`
- `CORP\IT_Admins`
- `MYDOMAIN\Finance_Team`

### Local Groups
- `Local_Admins`
- `Vault_Operators`
- `Safe_Managers`

### Distinguished Names (if applicable)
- `CN=GroupName,OU=Groups,DC=domain,DC=com`

## Important Notes

1. **Case Sensitivity**: Group names are case-sensitive. Ensure exact matches.
2. **Special Characters**: Escape special characters if needed in your environment.
3. **Validation**: The script will validate that mapping file exists and is readable.
4. **Empty Rows**: Empty rows in the mapping file will be skipped.
5. **Duplicates**: If duplicate old group names exist, the last mapping will be used.

## Creating Your Mapping File

### Method 1: Export from Active Directory
```powershell
# Export current groups to CSV for reference
Get-ADGroup -Filter * -SearchBase "OU=YourOU,DC=domain,DC=com" | 
    Select-Object Name, SamAccountName | 
    Export-Csv -Path "current-groups.csv" -NoTypeInformation
```

### Method 2: Manual Creation
1. Create a new CSV file in any text editor
2. Add your group mappings (one per line)
3. Save with .csv extension

### Method 3: Excel Spreadsheet
1. Open Excel
2. Create two columns with your group mappings
3. Save as .xlsx format

## Validation Tips

Before running the script:

1. **Verify Group Names**: Ensure all group names in your mapping file exist in your environment
2. **Check Permissions**: Confirm you have rights to modify safe permissions
3. **Test Mapping**: Start with a small subset of groups for testing
4. **Backup**: Consider exporting current safe permissions before making changes

## Sample PowerShell to Generate Mapping File

```powershell
# Create a sample mapping file programmatically
$mappings = @(
    @{Old="LEGACY_TEAM_1"; New="MODERN_TEAM_1"},
    @{Old="LEGACY_TEAM_2"; New="MODERN_TEAM_2"},
    @{Old="OLD_ADMINS"; New="NEW_ADMINS"}
)

$csvData = $mappings | ForEach-Object {
    [PSCustomObject]@{
        OldGroupName = $_.Old
        NewGroupName = $_.New
    }
}

$csvData | Export-Csv -Path "generated-mapping.csv" -NoTypeInformation
```
