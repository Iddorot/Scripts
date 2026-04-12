#Requires -Version 5.1
<#
.SYNOPSIS
    Entra ID Permissions Review Script

.DESCRIPTION
    Exports Entra role assignments (PIM active + eligible, and permanent) and
    role-related group memberships into a timestamped Excel workbook.

    Sheet 1 - EntraRoleAssignments : All active / eligible directory role assignments
    Sheet 2 - GroupMemberships     : Members of all groups whose name contains "role"

.NOTES
    Requirements:
      - Microsoft.Graph PowerShell SDK  (Install-Module Microsoft.Graph)
      - Microsoft Excel installed on the machine running the script
      - Permissions : RoleManagement.Read.All, Directory.Read.All,
                      Group.Read.All, GroupMember.Read.All, User.Read.All
#>

[CmdletBinding()]
param (
    # Output folder; defaults to the directory the script lives in
    [string]$OutputFolder = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# 0. Output file path
# ─────────────────────────────────────────────────────────────────────────────
$DateStamp  = Get-Date -Format "yyyy-MM-dd"
$OutputFile = Join-Path $OutputFolder "EntraRolesReview-$DateStamp.xlsx"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Connect to Microsoft Graph
# ─────────────────────────────────────────────────────────────────────────────
$RequiredScopes = @(
    "RoleManagement.Read.All",
    "Directory.Read.All",
    "Group.Read.All",
    "GroupMember.Read.All",
    "User.Read.All"
)

Write-Host "[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes $RequiredScopes -NoWelcome

$Context = Get-MgContext
Write-Host "[+] Connected as: $($Context.Account)`n" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 2. Helper – resolve a principal ID to display details
# ─────────────────────────────────────────────────────────────────────────────
$PrincipalCache = @{}

function Resolve-Principal {
    param([string]$Id)

    if ($PrincipalCache.ContainsKey($Id)) { return $PrincipalCache[$Id] }

    $result = $null

    # Try User
    try {
        $u = Get-MgUser -UserId $Id -Property "displayName,userPrincipalName,mail" -ErrorAction Stop
        $result = [PSCustomObject]@{
            DisplayName = $u.DisplayName
            Email       = if ($u.Mail)             { $u.Mail }             else { $u.UserPrincipalName }
            UPN         = $u.UserPrincipalName
            Type        = "User"
        }
    } catch { }

    # Try Group
    if (-not $result) {
        try {
            $g = Get-MgGroup -GroupId $Id -Property "displayName,mail" -ErrorAction Stop
            $result = [PSCustomObject]@{
                DisplayName = $g.DisplayName
                Email       = if ($g.Mail) { $g.Mail } else { "" }
                UPN         = ""
                Type        = "Group"
            }
        } catch { }
    }

    # Try Service Principal
    if (-not $result) {
        try {
            $sp = Get-MgServicePrincipal -ServicePrincipalId $Id -Property "displayName,appId" -ErrorAction Stop
            $result = [PSCustomObject]@{
                DisplayName = $sp.DisplayName
                Email       = ""
                UPN         = $sp.AppId
                Type        = "ServicePrincipal"
            }
        } catch { }
    }

    # Fallback
    if (-not $result) {
        $result = [PSCustomObject]@{
            DisplayName = "Unknown ($Id)"
            Email       = ""
            UPN         = ""
            Type        = "Unknown"
        }
    }

    $PrincipalCache[$Id] = $result
    return $result
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Helper – resolve role definition ID to display name
# ─────────────────────────────────────────────────────────────────────────────
$RoleDefCache = @{}

function Resolve-RoleName {
    param([string]$RoleDefinitionId)

    if ($RoleDefCache.ContainsKey($RoleDefinitionId)) { return $RoleDefCache[$RoleDefinitionId] }

    try {
        $def = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $RoleDefinitionId -ErrorAction Stop
        $RoleDefCache[$RoleDefinitionId] = $def.DisplayName
        return $def.DisplayName
    } catch {
        return $RoleDefinitionId
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Collect role assignment rows
# ─────────────────────────────────────────────────────────────────────────────
$RoleRows  = [System.Collections.Generic.List[PSCustomObject]]::new()
$PimActive = $false   # track whether PIM schedule data was retrieved

# ── 4a. PIM Active (time-bound activated assignments) ─────────────────────────
Write-Host "[*] Fetching PIM active assignment schedule instances..." -ForegroundColor Cyan
try {
    $ActiveInstances = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -All -ErrorAction Stop
    $PimActive = $true
    Write-Host "    Found $($ActiveInstances.Count) PIM active instances." -ForegroundColor Gray

    foreach ($ai in $ActiveInstances) {
        $p = Resolve-Principal -Id $ai.PrincipalId
        $RoleRows.Add([PSCustomObject]@{
            "Assignment State"            = "Active"
            "User Group Name"             = $p.DisplayName
            "Resource Name"               = "Tenant"
            "Role Name"                   = Resolve-RoleName $ai.RoleDefinitionId
            "Resource Type"               = "Directory"
            "Email"                       = $p.Email
            "PrincipalName"               = $p.UPN
            "Member Type"                 = if ($ai.MemberType) { $ai.MemberType } else { $p.Type }
            "Assignment Start Time (UTC)" = if ($ai.StartDateTime) { $ai.StartDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            "Assignment End Time (UTC)"   = if ($ai.EndDateTime)   { $ai.EndDateTime.ToString("yyyy-MM-dd HH:mm:ss") }   else { "Permanent" }
        })
    }
} catch {
    Write-Warning "PIM active schedules unavailable (no P2 license or insufficient permission). Falling back to permanent assignments."
}

# ── 4b. Fallback – permanent assignments (if PIM schedule data not available) ─
if (-not $PimActive) {
    Write-Host "[*] Fetching permanent role assignments..." -ForegroundColor Cyan
    $PermAssignments = Get-MgRoleManagementDirectoryRoleAssignment -All -ExpandProperty "roleDefinition" -ErrorAction SilentlyContinue
    Write-Host "    Found $($PermAssignments.Count) permanent assignments." -ForegroundColor Gray

    foreach ($pa in $PermAssignments) {
        $p = Resolve-Principal -Id $pa.PrincipalId
        $RoleRows.Add([PSCustomObject]@{
            "Assignment State"            = "Active"
            "User Group Name"             = $p.DisplayName
            "Resource Name"               = "Tenant"
            "Role Name"                   = if ($pa.RoleDefinition) { $pa.RoleDefinition.DisplayName } else { Resolve-RoleName $pa.RoleDefinitionId }
            "Resource Type"               = "Directory"
            "Email"                       = $p.Email
            "PrincipalName"               = $p.UPN
            "Member Type"                 = $p.Type
            "Assignment Start Time (UTC)" = ""
            "Assignment End Time (UTC)"   = "Permanent"
        })
    }
}

# ── 4c. PIM Eligible assignments ──────────────────────────────────────────────
Write-Host "[*] Fetching PIM eligible assignment schedule instances..." -ForegroundColor Cyan
try {
    $EligibleInstances = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -All -ErrorAction Stop
    Write-Host "    Found $($EligibleInstances.Count) eligible instances." -ForegroundColor Gray

    foreach ($ei in $EligibleInstances) {
        $p = Resolve-Principal -Id $ei.PrincipalId
        $RoleRows.Add([PSCustomObject]@{
            "Assignment State"            = "Eligible"
            "User Group Name"             = $p.DisplayName
            "Resource Name"               = "Tenant"
            "Role Name"                   = Resolve-RoleName $ei.RoleDefinitionId
            "Resource Type"               = "Directory"
            "Email"                       = $p.Email
            "PrincipalName"               = $p.UPN
            "Member Type"                 = if ($ei.MemberType) { $ei.MemberType } else { $p.Type }
            "Assignment Start Time (UTC)" = if ($ei.StartDateTime) { $ei.StartDateTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            "Assignment End Time (UTC)"   = if ($ei.EndDateTime)   { $ei.EndDateTime.ToString("yyyy-MM-dd HH:mm:ss") }   else { "No Expiry" }
        })
    }
} catch {
    Write-Warning "PIM eligible schedules unavailable: $_"
}

Write-Host "[+] Total role assignment rows collected: $($RoleRows.Count)`n" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 5. Collect group membership rows
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[*] Fetching all groups and filtering for names containing 'role'..." -ForegroundColor Cyan

# Graph OData does not support 'contains'; fetch all and filter locally
$AllGroups  = Get-MgGroup -All -Property "id,displayName,mail" -ErrorAction SilentlyContinue
$RoleGroups = $AllGroups | Where-Object { $_.DisplayName -match "role" }

Write-Host "[+] Found $($RoleGroups.Count) matching groups.`n" -ForegroundColor Green

$GroupRows = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($group in $RoleGroups) {
    Write-Host "    [→] Processing: $($group.DisplayName)" -ForegroundColor Gray
    try {
        $Members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop

        if ($Members.Count -eq 0) {
            $GroupRows.Add([PSCustomObject]@{
                "GroupName" = $group.DisplayName
                "User Name" = "(No members)"
                "Email"     = ""
                "Group Id"  = $group.Id
            })
        } else {
            foreach ($member in $Members) {
                $m = Resolve-Principal -Id $member.Id
                $GroupRows.Add([PSCustomObject]@{
                    "GroupName" = $group.DisplayName
                    "User Name" = $m.DisplayName
                    "Email"     = $m.Email
                    "Group Id"  = $group.Id
                })
            }
        }
    } catch {
        Write-Warning "Could not retrieve members for '$($group.DisplayName)': $_"
    }
}

Write-Host "[+] Total group membership rows collected: $($GroupRows.Count)`n" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 6. Write Excel workbook via COM Object
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[*] Building Excel workbook: $OutputFile" -ForegroundColor Cyan

$Excel                = New-Object -ComObject Excel.Application
$Excel.Visible        = $false
$Excel.DisplayAlerts  = $false
$Workbook             = $Excel.Workbooks.Add()

# ── Internal helper: write a dataset to a named sheet ────────────────────────
function Write-ExcelSheet {
    param(
        [object]   $Workbook,
        [int]      $SheetIndex,
        [string]   $SheetName,
        [string[]] $Headers,
        [System.Collections.Generic.List[PSCustomObject]] $Data
    )

    # Reuse existing sheet or add a new one
    if ($SheetIndex -le $Workbook.Sheets.Count) {
        $Sheet = $Workbook.Sheets.Item($SheetIndex)
    } else {
        $Sheet = $Workbook.Sheets.Add(
            [System.Reflection.Missing]::Value,
            $Workbook.Sheets.Item($Workbook.Sheets.Count)
        )
    }
    $Sheet.Name = $SheetName

    # ── Header row ────────────────────────────────────────────────────────────
    for ($col = 0; $col -lt $Headers.Count; $col++) {
        $cell = $Sheet.Cells.Item(1, $col + 1)
        $cell.Value2          = $Headers[$col]
        $cell.Font.Bold       = $true
        $cell.Font.Color      = [System.Drawing.ColorTranslator]::ToOle([System.Drawing.Color]::White)
        $cell.Interior.Color  = [System.Drawing.ColorTranslator]::ToOle([System.Drawing.Color]::FromArgb(31, 73, 125))  # dark blue
    }

    # ── Data rows ─────────────────────────────────────────────────────────────
    $rowIndex = 2
    foreach ($record in $Data) {
        for ($col = 0; $col -lt $Headers.Count; $col++) {
            $value = $record.($Headers[$col])
            $Sheet.Cells.Item($rowIndex, $col + 1).Value2 = if ($null -ne $value) { "$value" } else { "" }
        }

        # Alternate row shading for readability
        if ($rowIndex % 2 -eq 0) {
            $Sheet.Rows.Item($rowIndex).Interior.Color = [System.Drawing.ColorTranslator]::ToOle([System.Drawing.Color]::FromArgb(217, 226, 243))
        }
        $rowIndex++
    }

    # ── Formatting ────────────────────────────────────────────────────────────
    $null = $Sheet.UsedRange.EntireColumn.AutoFit()   # auto-fit column widths
    $null = $Sheet.Rows.Item(1).AutoFilter()          # enable header filter
    $Sheet.Activate()
    $null = $Sheet.Application.ActiveWindow.FreezePanes = $false
    $Sheet.Rows.Item(2).Select() | Out-Null
    $Sheet.Application.ActiveWindow.FreezePanes = $true  # freeze header row

    Write-Host "    [✓] Sheet '$SheetName' written ($($Data.Count) rows)." -ForegroundColor Gray
}

# ── Sheet 1: EntraRoleAssignments ─────────────────────────────────────────────
$Sheet1Headers = @(
    "Assignment State",
    "User Group Name",
    "Resource Name",
    "Role Name",
    "Resource Type",
    "Email",
    "PrincipalName",
    "Member Type",
    "Assignment Start Time (UTC)",
    "Assignment End Time (UTC)"
)

Write-ExcelSheet -Workbook $Workbook `
                 -SheetIndex 1 `
                 -SheetName "EntraRoleAssignments" `
                 -Headers $Sheet1Headers `
                 -Data $RoleRows

# ── Sheet 2: GroupMemberships ─────────────────────────────────────────────────
$Sheet2Headers = @("GroupName", "User Name", "Email", "Group Id")

Write-ExcelSheet -Workbook $Workbook `
                 -SheetIndex 2 `
                 -SheetName "GroupMemberships" `
                 -Headers $Sheet2Headers `
                 -Data $GroupRows

# ── Remove any extra default sheets ──────────────────────────────────────────
while ($Workbook.Sheets.Count -gt 2) {
    $Workbook.Sheets.Item($Workbook.Sheets.Count).Delete()
}

# ── Activate Sheet 1 on open ──────────────────────────────────────────────────
$Workbook.Sheets.Item(1).Activate()

# ── Save & release COM objects ────────────────────────────────────────────────
$Workbook.SaveAs($OutputFile, 51)   # 51 = xlOpenXMLWorkbook (.xlsx)
$Workbook.Close($false)
$Excel.Quit()

[System.Runtime.InteropServices.Marshal]::ReleaseComObject($Workbook) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($Excel)    | Out-Null
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

Write-Host "[+] Workbook saved: $OutputFile`n" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 7. Disconnect
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[*] Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
Disconnect-MgGraph | Out-Null
Write-Host "[✓] All done." -ForegroundColor Green
