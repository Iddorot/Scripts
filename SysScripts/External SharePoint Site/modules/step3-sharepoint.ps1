# =============================================================================
# modules/step3-sharepoint.ps1
#
# Creates a SharePoint Communication Site for the project, sets sharing to
# ExistingExternalUserSharingOnly, and assigns the Entra group as Site Members.
#
# Uses PnP PowerShell (PnP.PowerShell module).
#   Install-Module PnP.PowerShell -Scope CurrentUser
#
# Required:
#   SharePoint Administrator role
# =============================================================================


# --------------------------------------------------------------------------
# Connect-ProjectSharePoint                       <- internal helper
#   Opens an interactive PnP connection to the given URL using a client ID.
# --------------------------------------------------------------------------
function Connect-ProjectSharePoint {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$ClientId
    )

    Write-Log "INFO" "Connecting to SharePoint: $Url  (ClientId: $ClientId)"
    Connect-PnPOnline -Url $Url -ClientId $ClientId -Interactive -ErrorAction Stop
}


# --------------------------------------------------------------------------
# Get-SharePointSite
#   Returns the site object if the URL already exists, otherwise $null.
# --------------------------------------------------------------------------
function Get-SharePointSite {
    param(
        [Parameter(Mandatory)][string]$TenantUrl,
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$ClientId
    )

    try {
        Connect-ProjectSharePoint -Url $TenantUrl -ClientId $ClientId
        return Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue
    }
    catch { return $null }
}


# --------------------------------------------------------------------------
# New-ProjectSharePointSite
#   Creates a Communication Site, waits for provisioning, returns the site object.
# --------------------------------------------------------------------------
function New-ProjectSharePointSite {
    param(
        [Parameter(Mandatory)][string]$TenantUrl,
        [Parameter(Mandatory)][string]$SiteTitle,
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$ClientId
    )

    Write-Log "INFO" "Creating SharePoint site: $SiteTitle ($SiteUrl)"

    try {
        Connect-ProjectSharePoint -Url $TenantUrl -ClientId $ClientId

        New-PnPSite -Type CommunicationSite `
                    -Title $SiteTitle `
                    -Url   $SiteUrl `
                    -ErrorAction Stop | Out-Null

        Write-Log "INFO" "Waiting for site provisioning..."
        $timeout = 120; $elapsed = 0
        do {
            Start-Sleep -Seconds 10; $elapsed += 10
            $site = Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue
        } while ((-not $site) -and $elapsed -lt $timeout)

        if (-not $site) { throw "Site did not appear after $timeout seconds." }

        Write-Log "SUCCESS" "Site provisioned: $SiteUrl"
        return $site
    }
    catch {
        Write-Log "ERROR" "Failed to create SharePoint site: $_"
        throw
    }
}


# --------------------------------------------------------------------------
# Set-SiteExternalSharing
#   Sets sharing to ExistingExternalUserSharingOnly (already-invited users only).
# --------------------------------------------------------------------------
function Set-SiteExternalSharing {
    param(
        [Parameter(Mandatory)][string]$TenantUrl,
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$ClientId
    )

    Write-Log "INFO" "Enabling external sharing on $SiteUrl"

    Connect-ProjectSharePoint -Url $TenantUrl -ClientId $ClientId

    try {
        Set-PnPTenantSite -Url $SiteUrl `
            -SharingCapability ExistingExternalUserSharingOnly `
            -ErrorAction Stop
        Write-Log "SUCCESS" "External sharing set to 'ExistingExternalUserSharingOnly' (already-invited users only)."
    }
    catch {
        Write-Log "ERROR" "Failed to set sharing capability: $_"
        throw
    }
}


# --------------------------------------------------------------------------
# Add-GroupAsSiteMembers
#   Adds the Entra security group to the site's Members SharePoint group.
# --------------------------------------------------------------------------
function Add-GroupAsSiteMembers {
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$ClientId
    )

    Write-Log "INFO" "Adding Entra group $GroupId as Members on $SiteUrl"

    try {
        Connect-ProjectSharePoint -Url $SiteUrl -ClientId $ClientId

        $spMembers = Get-PnPGroup -AssociatedMemberGroup -ErrorAction Stop

        Add-PnPGroupMember -Group     $spMembers `
                           -LoginName "c:0t.c|tenant|$GroupId" `
                           -ErrorAction Stop

        Write-Log "SUCCESS" "Group added to site Members."
    }
    catch {
        Write-Log "ERROR" "Failed to add group to site members: $_"
        throw
    }
}


# --------------------------------------------------------------------------
# Invoke-Step3-SharePoint                     <- main entry point for step 3
#   Returns a result object: { SiteUrl; AlreadyExisted }
#
#   Config must include: SPTenantUrl, SiteAlias, SiteTitle, SiteUrl
# --------------------------------------------------------------------------
function Invoke-Step3-SharePoint {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$ClientId
    )

    Write-Log "STEP" "--- Step 3: SharePoint Site [$($Config.SiteTitle)] ---"

    $existing = Get-SharePointSite -TenantUrl $Config.SPAdminUrl -SiteUrl $Config.SiteUrl -ClientId $ClientId

    if ($existing) {
        Write-Log "SKIP" "Site '$($Config.SiteUrl)' already exists - verifying settings..."
    } else {
        New-ProjectSharePointSite `
            -TenantUrl  $Config.SPAdminUrl `
            -SiteTitle  $Config.SiteTitle `
            -SiteUrl    $Config.SiteUrl `
            -ClientId   $ClientId
    }

    Set-SiteExternalSharing -TenantUrl $Config.SPAdminUrl -SiteUrl $Config.SiteUrl -ClientId $ClientId
    Add-GroupAsSiteMembers  -SiteUrl $Config.SiteUrl -GroupId $GroupId -ClientId $ClientId

    Write-Log "SUCCESS" "Step 3 complete - site ready at $($Config.SiteUrl)"
    return [PSCustomObject]@{
        SiteUrl        = $Config.SiteUrl
        AlreadyExisted = [bool]$existing
    }
}
