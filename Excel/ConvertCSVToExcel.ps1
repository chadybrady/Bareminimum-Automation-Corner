# Install the ImportExcel module (if not already installed)
Install-Module -Name ImportExcel -Force


# Define the source and destination directories
$sourceDir = Read-Host 'Enter the source directory path (where CSV files are located)'
$destinationDir = Read-Host 'Enter the destination directory path (where Excel files will be saved)'


# Ensure the source directory exists
if (!(Test-Path -Path $sourceDir)) {
    Write-Error "Source directory does not exist: $sourceDir"
    exit 1
}

# Ensure the destination directory exists
if (!(Test-Path -Path $destinationDir)) {
    Write-Output "Creating destination directory: $destinationDir"
    New-Item -ItemType Directory -Path $destinationDir
}

# Get all CSV files in the source directory
$csvFiles = Get-ChildItem -Path $sourceDir -Filter "*.csv"

# Check if there are any CSV files
if ($csvFiles.Count -eq 0) {
    Write-Output "No CSV files found in the source directory."
    exit
}

# Log the number of CSV files found
Write-Output "Found $($csvFiles.Count) CSV files in the source directory."

# Loop through each CSV file and convert it to Excel format
foreach ($csvFile in $csvFiles) {
    # Log the current file being processed
    Write-Output "Processing file: $($csvFile.Name)"

    # Import the CSV file
    try {
        $csvData = Import-Csv -Path $csvFile.FullName
        Write-Output "Successfully imported $($csvFile.Name)"
    } catch {
        Write-Error "Failed to import $($csvFile.Name): $_"
        continue
    }

    # Define the Excel file path
    $excelFilePath = Join-Path -Path $destinationDir -ChildPath ($csvFile.BaseName + ".xlsx")

    # Export to Excel
    try {
        $csvData | Export-Excel -Path $excelFilePath
        Write-Output "Converted $($csvFile.Name) to $($csvFile.BaseName).xlsx and moved to $destinationDir"
    } catch {
        Write-Error "Failed to convert $($csvFile.Name) to Excel: $_"
    }
}

Write-Output "Script completed successfully."
