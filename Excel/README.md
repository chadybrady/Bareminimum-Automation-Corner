# 📊 Excel Utilities

PowerShell scripts for **Excel file manipulation and conversion**.

---

## 📄 Scripts

### `ConvertCSVToExcel.ps1`

Bulk-converts CSV files to Excel (`.xlsx`) format.

**Features:**
- Processes all CSV files in a source directory
- Converts each CSV to Excel format and saves to a destination directory
- Automatically creates the destination directory if it doesn't exist
- Preserves original CSV files
- Provides detailed progress and error logging with per-file error handling

---

## ⚙️ Prerequisites

- PowerShell 5.1 or later
- `ImportExcel` PowerShell module (auto-installed if not present)

---

## 🚀 Usage

```powershell
.\ConvertCSVToExcel.ps1
```

The script will interactively prompt for:
1. **Source directory path** — where the CSV files are located
2. **Destination directory path** — where the converted Excel files will be saved

**Example:**

```powershell
Enter the source directory path: C:\Data\CSVFiles
Enter the destination directory path: C:\Data\ExcelFiles
```

---

## 🔗 Related Links

- [ImportExcel module](https://github.com/dfinke/ImportExcel)
