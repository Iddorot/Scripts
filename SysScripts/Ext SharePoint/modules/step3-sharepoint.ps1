# =============================================================================
# modules/step3-sharepoint.ps1
#
# Creates a SharePoint Communication Site for the project, enables external
# sharing, and assigns the Entra group as Site Members.
#
# Uses PnP PowerShell (PnP.PowerShell module).
#   Install-Module PnP.PowerShell -Scope CurrentUser
#
# Required:
#   SharePoint Administrator role  OR  Sites.FullControl.All Graph scope
# =============================================================================

# --------------------------------------------------------------------------
# Get-SharePointSite
#   Returns the site object if the URL already exists, otherwise $null.
# --------------------------------------------------------------------------
function Get-SharePointSite {
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$AdminUrl
    )

    try {
        Connect-PnPOnline -Url $AdminUrl -UseWebLogin -ErrorAction Stop
        $site = Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue
        return $site
    }
    catch { return $null }
}

# --------------------------------------------------------------------------
# New-ProjectSharePointSite
#   Creates a Communication Site, enables ExternalUserAndGuestSharing,
#   waits for provisioning, then returns the site URL.
# --------------------------------------------------------------------------
function New-ProjectSharePointSite {
    param(
        [Parameter(Mandatory)][string]$AdminUrl,
        [Parameter(Mandatory)][string]$SiteAlias,
        [Parameter(Mandatory)][string]$SiteTitle,
        [Parameter(Mandatory)][string]$SiteUrl
    )

    Write-Log "INFO" "Creating SharePoint site: $SiteTitle ($SiteUrl)"

    try {
        Connect-PnPOnline -Url $AdminUrl -UseWebLogin -ErrorAction Stop

        # Create team site (can swap Template to "SITEPAGEPUBLISHING#0" for Comms site)
        New-PnPSite -Type TeamSite `
                    -Title $SiteTitle `
                    -Alias $SiteAlias `
                    -IsPublic:$false `
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
#   Sets the sharing capability to ExternalUserAndGuestSharing.
# --------------------------------------------------------------------------
function Set-SiteExternalSharing {
    param(
        [Parameter(Mandatory)][string]$AdminUrl,
        [Parameter(Mandatory)][string]$SiteUrl
    )

    Write-Log "INFO" "Enabling external sharing on $SiteUrl"

    try {
        Connect-PnPOnline -Url $AdminUrl -UseWebLogin -ErrorAction Stop
        Set-PnPTenantSite -Url $SiteUrl `
            -SharingCapability ExternalUserAndGuestSharing `
            -ErrorAction Stop
        Write-Log "SUCCESS" "External sharing enabled."
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
        [Parameter(Mandatory)][string]$GroupId    # Entra group object ID
    )

    Write-Log "INFO" "Adding Entra group $GroupId as Members on $SiteUrl"

    try {
        Connect-PnPOnline -Url $SiteUrl -UseWebLogin -ErrorAction Stop

        # Resolve SharePoint Members group name (usually "<SiteTitle> Members")
        $spMembers = Get-PnPGroup -AssociatedMemberGroup -ErrorAction Stop

        Add-PnPGroupMember -Group $spMembers `
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
# --------------------------------------------------------------------------
function Invoke-Step3-SharePoint {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$GroupId
    )

    Write-Log "STEP" "--- Step 3: SharePoint Site [$($Config.SiteTitle)] ---"

    # Check if site already exists
    $existing = Get-SharePointSite -SiteUrl $Config.SiteUrl -AdminUrl $Config.SPAdminUrl

    if ($existing) {
        Write-Log "SKIP" "Site '$($Config.SiteUrl)' already exists."
    } else {
        New-ProjectSharePointSite `
            -AdminUrl   $Config.SPAdminUrl `
            -SiteAlias  $Config.SiteAlias `
            -SiteTitle  $Config.SiteTitle `
            -SiteUrl    $Config.SiteUrl
    }

    # Always ensure sharing + membership are correct
    Set-SiteExternalSharing -AdminUrl $Config.SPAdminUrl -SiteUrl $Config.SiteUrl
    Add-GroupAsSiteMembers  -SiteUrl  $Config.SiteUrl    -GroupId $GroupId

    Write-Log "SUCCESS" "Step 3 complete - site ready at $($Config.SiteUrl)"
    return [PSCustomObject]@{
        SiteUrl       = $Config.SiteUrl
        AlreadyExisted = [bool]$existing
    }
}
 