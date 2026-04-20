# Excel Utilities

PowerShell scripts for Excel file manipulation and conversion.

## Scripts

### ConvertCSVToExcel.ps1

Converts CSV files to Excel (.xlsx) format in bulk. This script:
- Processes all CSV files in a source directory
- Converts each CSV to Excel format
- Saves converted files to a destination directory
- Provides detailed progress and error logging

**Prerequisites**:
- `ImportExcel` PowerShell module (auto-installed if not present)

**Usage**:
```powershell
.\ConvertCSVToExcel.ps1
```

The script will prompt for:
1. Source directory path (where CSV files are located)
2. Destination directory path (where Excel files will be saved)

**Features**:
- Automatically creates destination directory if it doesn't exist
- Preserves original CSV files
- Provides detailed logging of conversion process
- Error handling for individual file failures

## Example

```powershell
# Run the script
.\ConvertCSVToExcel.ps1

# When prompted
Enter the source directory path: C:\Data\CSVFiles
Enter the destination directory path: C:\Data\ExcelFiles
```

The script will process all CSV files and create corresponding .xlsx files in the destination directory.

## Notes

💡 The ImportExcel module will be automatically installed if not present on your system.
