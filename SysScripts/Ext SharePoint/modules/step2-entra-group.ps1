# =============================================================================
# modules/step2-entra-group.ps1
#
# Creates (or verifies) the Entra security group:
#   sharepoint-ext-{project}-members
#
# Graph API surfaces used:
#   GET  /v1.0/groups?$filter=displayName eq '{name}'
#   POST /v1.0/groups
#
# Required scopes:
#   Group.ReadWrite.All
# =============================================================================

# --------------------------------------------------------------------------
# Get-EntraGroupByName
#   Returns the group object if a group with that exact display name exists,
#   otherwise returns $null.
# --------------------------------------------------------------------------
function Get-EntraGroupByName {
    param([Parameter(Mandatory)][string]$DisplayName)

    $encoded = [Uri]::EscapeDataString($DisplayName)
    $uri     = "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$encoded'&`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled"

    try {
        $result = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        if ($result.value.Count -gt 0) { return $result.value[0] }
        return $null
    }
    catch {
        Write-Log "ERROR" "Failed to query groups: $_"
        throw
    }
}

# --------------------------------------------------------------------------
# New-EntraSecurityGroup
#   Creates a mail-enabled security group (required by SharePoint/Entitlement)
#   Returns the new group object.
# --------------------------------------------------------------------------
function New-EntraSecurityGroup {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Description,
        [string]$MailNickname      # defaults to sanitised DisplayName
    )

    if (-not $MailNickname) {
        $MailNickname = $DisplayName.ToLower() -replace '[^a-z0-9]', ''
    }

    $body = @{
        displayName     = $DisplayName
        description     = $Description
        mailEnabled     = $false
        mailNickname    = $MailNickname
        securityEnabled = $true
        groupTypes      = @()      # plain security group (no Unified/M365)
    } | ConvertTo-Json

    try {
        $uri    = "https://graph.microsoft.com/v1.0/groups"
        $result = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Log "SUCCESS" "Group created: $DisplayName (id=$($result.id))"
        return $result
    }
    catch {
        $err     = $_
        $errBody = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        Write-Log "ERROR" "Failed to create group: $($errBody.error.message) $err"
        throw
    }
}

# --------------------------------------------------------------------------
# Invoke-Step2-EntraGroup                     <- main entry point for step 2
#   Returns a result object: { GroupId; GroupName; AlreadyExisted }
# --------------------------------------------------------------------------
function Invoke-Step2-EntraGroup {
    param([Parameter(Mandatory)][PSCustomObject]$Config)

    Write-Log "STEP" "--- Step 2: Entra Group [$($Config.GroupName)] ---"

    # Check if already exists
    $existing = Get-EntraGroupByName -DisplayName $Config.GroupName

    if ($existing) {
        Write-Log "SKIP" "Group '$($Config.GroupName)' already exists (id=$($existing.id))."
        return [PSCustomObject]@{
            GroupId       = $existing.id
            GroupName     = $existing.displayName
            AlreadyExisted = $true
        }
    }

    $group = New-EntraSecurityGroup `
        -DisplayName  $Config.GroupName `
        -Description  $Config.GroupDescription

    Write-Log "SUCCESS" "Step 2 complete - group '$($group.displayName)' ready."
    return [PSCustomObject]@{
        GroupId       = $group.id
        GroupName     = $group.displayName
        AlreadyExisted = $false
    }
}