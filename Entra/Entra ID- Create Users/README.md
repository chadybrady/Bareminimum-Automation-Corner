# Entra user provisioning

`Create-EntraUserBulkAndSingle.ps1` creates **cloud-only Member users** interactively or from CSV/XLSX input. It does not modify existing users, invite Guests, assign licenses, add groups, or configure mailboxes.

## Requirements

- PowerShell 7+
- Internet access to install `Microsoft.Graph.Authentication` and `Microsoft.Graph.Users` if absent
- `ImportExcel` only when importing XLSX
- A Graph role and delegated consent sufficient for `User.ReadWrite.All`

The script uses Microsoft Graph `v1.0`. Creation and manager assignment are **write operations**. Run `-WhatIf` first in every new tenant or source file.

The script installs and imports its Microsoft Graph dependencies when needed. It reuses an open Graph session that has `User.ReadWrite.All`; otherwise it prompts for browser or device-code sign-in. Use `-TenantId` and `-AuthenticationMode Browser` or `-AuthenticationMode DeviceCode` to avoid prompts.

## Input columns

The existing English template remains supported. A supplied Swedish worksheet can also use the headers below; `Visningsnamn` takes precedence over `Namn` for the display name.

| Entra ID property | English header | Swedish header |
|---|---|---|
| User principal name | `UserPrincipalName` | `Användarens inloggningsnamn` |
| Display name | `DisplayName` | `Visningsnamn`, or `Namn` when `Visningsnamn` is blank |
| Given name | `GivenName` | `Förnamn` |
| Surname | `Surname` | `Efternamn` |
| Mail nickname | `MailNickname` | `Inloggningsnamn före Windows 2000` |
| Company | `CompanyName` | `Företag` |
| Department | `Department` | `Avdelning` |
| Job title | `JobTitle` | `Befattning` |
| About me | `AboutMe` | `Beskrivning` |
| City | `City` | `Ort` |
| Postal code | `PostalCode` | `Postnummer` |
| Business phone | `BusinessPhone` or `BusinessPhones` | `Telefonnummer` |
| Mobile phone | `MobilePhone` | `Mobilnummer` |
| Email address | `Mail` | `E-postadress` |

Optional:

- `MailNickname` / `Inloggningsnamn före Windows 2000` — defaults to the UPN portion before `@`; unsupported characters are removed
- `UsageLocation` — two-letter ISO country/region code, for example `SE`
- `AccountEnabled` — defaults to `true`; accepts `true/false`, `yes/no`, or `1/0`
- `ManagerUserPrincipalName` — resolves and assigns the manager after creation; the manager may be another user in the same input

`Beskrivning` maps to the Graph `aboutMe` property. Microsoft Graph requires `aboutMe` to be set after user creation, so the script sends it in a separate `PATCH /v1.0/users/{id}` request only after a successful user `POST`. The supplied source does not contain a cloud-writable equivalent for the Windows 2000 logon name, so it is used as the mail nickname.

### Swedish source creation marker

When the input includes `Redan Skapad:`, the script evaluates it before connecting to Microsoft Graph or looking up a UPN:

- Blank: eligible for validation and provisioning.
- `Ja`, `Yes`, `True`, `1`, `Created`, or `Skapad` (case-insensitive): skipped with `SourceDisposition` set to `SkippedBySourceMarker`.
- Any other nonblank value: recorded as `Failed` with `SourceDisposition` set to `InvalidSourceMarker`; no user is created.

The script never changes the source CSV or XLSX, including the marker column. It writes this disposition and the original marker only to the password-free results file.

Use `UserImportTemplate.csv` as the header and formatting reference. XLSX uses the first worksheet unless `-WorksheetName` is supplied.

## Safe operation

Preview interactive creation:

    ./Create-EntraUserBulkAndSingle.ps1 -Mode Single -WhatIf

Preview a CSV:

    ./Create-EntraUserBulkAndSingle.ps1 -SourcePath ./UserImportTemplate.csv -WhatIf

Create from CSV:

    ./Create-EntraUserBulkAndSingle.ps1 -SourcePath ./UserImportTemplate.csv -AllowPlainTextPasswordExport

Create from an Excel worksheet:

    ./Create-EntraUserBulkAndSingle.ps1 -SourcePath ./Users.xlsx -WorksheetName Users -AllowPlainTextPasswordExport

Existing UPNs are reported as `Skipped`; the script never updates them. Invalid or failing input rows are reported individually while other valid rows continue.

## Generated passwords

Each created user receives a unique, cryptographically generated password and must change it at next sign-in. Passwords are never included in the ordinary results CSV.

Because the chosen handoff method is a CSV, actual creation requires `-AllowPlainTextPasswordExport`. This deliberate acknowledgement permits a second file named `EntraUserPasswords-DELETE-AFTER-USE-*.csv` containing plaintext credentials. Store it only in an approved secure location, distribute passwords through an approved channel, and delete the file immediately afterward.

## Outputs

- `EntraUserResults-*.csv`: source row, UPN, object ID, creation status, source disposition and marker, `ProfileStatus`, manager status, and errors; contains no passwords. A failed post-create description update leaves `Status` as `Created` and records `ProfileStatus` as `Failed`.
- `EntraUserPasswords-DELETE-AFTER-USE-*.csv`: created-user UPNs and plaintext initial passwords; created only when users were created.

Use a non-production tenant for the first live validation. Verify that each account requires a password change and that any manager relationship is correct before operational rollout.
