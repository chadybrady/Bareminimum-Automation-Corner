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
    CompanyName    = 'Contoso Ltd'
    Manager        = 'manager@contoso.com'
    Groups         = '00000000-0000-0000-0000-000000000000'
    EligibleGroups = '00000000-0000-0000-0000-000000000000'
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
    7  = "CompanyName`nOptional. Company name set on the Entra user object."
    8  = "Manager`nOptional. UPN, display name, or Object ID of the manager."
    9  = "Groups`n! Object IDs (GUIDs) only - display names are NOT supported.`nAdds the user as a PERMANENT direct member of the group.`nSeparate multiple values with a semicolon (;).`nFind the ID in: Entra ID > Groups > <group> > Overview."
    10 = "EligibleGroups`n! Object IDs (GUIDs) only - display names are NOT supported.`nAdds the user as a PIM ELIGIBLE member of a role-assignable (PIM-enabled) group.`nThe group must have been created with 'Azure AD roles can be assigned to the group' enabled.`nSeparate multiple values with a semicolon (;).`nFind the ID in: Entra ID > Groups > <group> > Overview."
    11 = "PermanentRoles`nOptional. Entra role display names for permanent assignment.`nSeparate multiple values with a semicolon (;).`nExample: Exchange Administrator;User Administrator"
    12 = "EligibleRoles`nOptional. Entra role display names for PIM eligible assignment (no expiry).`nSeparate multiple values with a semicolon (;).`nExample: Global Administrator"
}

foreach ($col in $headerComments.Keys) {
    $cell    = $ws.Cells[1, $col]
    $comment = $ws.Comments.Add($cell, $headerComments[$col], 'Note')
    $comment.AutoFit = $true
}

# ── Style example row (row 2) as italic gray ──────────────────────────────────
for ($col = 1; $col -le $headerComments.Count; $col++) {
    $ws.Cells[2, [int]$col].Style.Font.Italic = $true
    try {
        $ws.Cells[2, [int]$col].Style.Font.Color.SetColor([System.Drawing.Color]::Gray)
    } catch { <# System.Drawing not available on this platform #> }
}

# Comment on A2 to flag it as example data
$exNote = $ws.Comments.Add($ws.Cells[2, 1],
    'Example row — shows expected format and GUID placeholder for Groups. Delete this row before running the script.', 'Tip')
$exNote.AutoFit = $true

Close-ExcelPackage $pkg -Show:$false
Write-Host "Template created: $outPath"
