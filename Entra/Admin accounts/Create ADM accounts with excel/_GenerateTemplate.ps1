# Helper script — run once to regenerate AdminUsers-Template.xlsx
# Delete this file after generating the template if desired.

Import-Module ImportExcel -ErrorAction Stop

$example = [PSCustomObject]@{
    FirstName      = 'John'
    LastName       = 'Doe'
    Domain         = 'contoso.com'
    DisplayName    = ''
    Department     = 'IT'
    JobTitle       = 'IT Administrator'
    Manager        = 'manager@contoso.com'
    Groups         = '00000000-0000-0000-0000-000000000000'
    PermanentRoles = 'Exchange Administrator'
    EligibleRoles  = 'Global Administrator'
}

$outPath = Join-Path $PSScriptRoot 'AdminUsers-Template.xlsx'

$excelParams = @{
    Path          = $outPath
    WorksheetName = 'AdminUsers'
    AutoSize      = $true
    BoldTopRow    = $true
    FreezeTopRow  = $true
    TableName     = 'AdminUsers'
    TableStyle    = 'Medium2'
    ClearSheet    = $true
}

$pkg = $example | Export-Excel @excelParams -PassThru
$ws  = $pkg.Workbook.Worksheets['AdminUsers']

# ── Column header comments ────────────────────────────────────────────────────
$headerComments = [ordered]@{
    1  = "FirstName`nRequired. First name of the admin account holder."
    2  = "LastName`nRequired. Last name of the admin account holder."
    3  = "Domain`nOptional. Overrides the global domain for this row only.`nExample: contoso.com"
    4  = "DisplayName`nOptional. Leave blank to auto-generate as: CADM - FirstName LastName"
    5  = "Department`nOptional. Department set on the Entra user object."
    6  = "JobTitle`nOptional. Job title set on the Entra user object."
    7  = "Manager`nOptional. UPN, display name, or Object ID of the manager."
    8  = "Groups`n! Object IDs (GUIDs) only - display names are NOT supported.`nSeparate multiple values with a semicolon (;).`nFind the ID in: Entra ID > Groups > <group> > Overview.`nExample: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx;yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
    9  = "PermanentRoles`nOptional. Entra role display names for permanent assignment.`nSeparate multiple values with a semicolon (;).`nExample: Exchange Administrator;User Administrator"
    10 = "EligibleRoles`nOptional. Entra role display names for PIM eligible assignment (no expiry).`nSeparate multiple values with a semicolon (;).`nExample: Global Administrator"
}

foreach ($col in $headerComments.Keys) {
    $cell    = $ws.Cells[1, $col]
    $comment = $ws.Comments.Add($cell, $headerComments[$col], 'Note')
    $comment.AutoFit = $true
}

# ── Style example row (row 2) as italic gray ──────────────────────────────────
for ($col = 1; $col -le 10; $col++) {
    $ws.Cells[2, $col].Style.Font.Italic = $true
    $ws.Cells[2, $col].Style.Font.Color.SetColor([System.Drawing.Color]::Gray)
}

# Comment on A2 to flag it as example data
$exNote = $ws.Comments.Add($ws.Cells[2, 1],
    'Example row — shows expected format and GUID placeholder for Groups. Delete this row before running the script.', 'Tip')
$exNote.AutoFit = $true

Close-ExcelPackage $pkg -Show:$false
Write-Host "Template created: $outPath"
