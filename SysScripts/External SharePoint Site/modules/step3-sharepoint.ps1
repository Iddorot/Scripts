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
#
# One-time setup — run Register-ProjectPnPApp once to create the cert & app
#   registration, then store the returned ClientId in your config.
# =============================================================================


# --------------------------------------------------------------------------
# Register-ProjectPnPApp                         <- run ONCE per environment
#   Creates the Entra app registration and writes two certificate files
#   (.pfx / .cer) to $CertFolder.  Returns the ClientId string.
#
#   After running, store the ClientId in your config file / secret store.
#   Sign in with your Admin account when the interactive browser prompt
#   appears.
# --------------------------------------------------------------------------
function Register-ProjectPnPApp {
    param(
        [Parameter(Mandatory)][string]$ApplicationName,   # e.g. "MySharePointApp"
        [Parameter(Mandatory)][string]$TenantName,        # e.g. "contoso"  (no .onmicrosoft.com)
        [Parameter(Mandatory)][string]$CertFolder         # e.g. "C:\PnPCerts"  — no spaces
    )

    # Ensure the cert folder exists
    if (-not (Test-Path $CertFolder)) {
        New-Item -ItemType Directory -Path $CertFolder -Force | Out-Null
        Write-Log "INFO" "Created certificate folder: $CertFolder"
    }

    Write-Log "INFO" "Registering Entra app '$ApplicationName' for tenant $TenantName.onmicrosoft.com"
    Write-Log "INFO" "A browser window will open — sign in with your Admin account."

    $result = Register-PnPEntraIDApp `
        -ApplicationName $ApplicationName `
        -Tenant          "$TenantName.onmicrosoft.com" `
        -OutPath         $CertFolder `
        -Interactive

    $clientId = $result.'AzureAppId/ClientId'

    if (-not $clientId) {
        Write-Log "ERROR" "Registration did not return a ClientId. Check the output above."
        throw "App registration failed."
    }

    Write-Log "SUCCESS" "App registered. ClientId: $clientId"
    Write-Log "INFO"    "Certificate files written to: $CertFolder"
    Write-Log "INFO"    "Store the ClientId — you will need it for every Connect call."

    return $clientId
}


# --------------------------------------------------------------------------
# Connect-ProjectSharePoint                       <- internal helper
#   Opens a cert-based PnP connection to the given URL.
#   Called by every function that needs a live connection.
# --------------------------------------------------------------------------
function Connect-ProjectSharePoint {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$TenantName,        # e.g. "contoso"
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertFolder,
        [Parameter(Mandatory)][string]$ApplicationName    # must match the .pfx filename
    )

    $certPath = Join-Path $CertFolder "$ApplicationName.pfx"

    Connect-PnPOnline `
        -Url             $Url `
        -ClientId        $ClientId `
        -Tenant          "$TenantName.onmicrosoft.com" `
        -CertificatePath $certPath `
        -ErrorAction     Stop
}


# --------------------------------------------------------------------------
# Get-SharePointSite
#   Returns the site object if the URL already exists, otherwise $null.
# --------------------------------------------------------------------------
function Get-SharePointSite {
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$TenantName,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertFolder,
        [Parameter(Mandatory)][string]$ApplicationName
    )

    try {
        Connect-ProjectSharePoint `
            -Url             "https://$TenantName.sharepoint.com" `
            -TenantName      $TenantName `
            -ClientId        $ClientId `
            -CertFolder      $CertFolder `
            -ApplicationName $ApplicationName

        $site = Get-PnPTenantSite -Url $SiteUrl -ErrorAction SilentlyContinue
        return $site
    }
    catch { return $null }
}


# --------------------------------------------------------------------------
# New-ProjectSharePointSite
#   Creates a Team Site (swap Template to SITEPAGEPUBLISHING#0 for Comms),
#   waits for provisioning, then returns the site object.
# --------------------------------------------------------------------------
function New-ProjectSharePointSite {
    param(
        [Parameter(Mandatory)][string]$TenantName,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertFolder,
        [Parameter(Mandatory)][string]$ApplicationName,
        [Parameter(Mandatory)][string]$SiteAlias,
        [Parameter(Mandatory)][string]$SiteTitle,
        [Parameter(Mandatory)][string]$SiteUrl
    )

    Write-Log "INFO" "Creating SharePoint site: $SiteTitle ($SiteUrl)"

    try {
        Connect-ProjectSharePoint `
            -Url             "https://$TenantName.sharepoint.com" `
            -TenantName      $TenantName `
            -ClientId        $ClientId `
            -CertFolder      $CertFolder `
            -ApplicationName $ApplicationName

        New-PnPSite -Type TeamSite `
                    -Title    $SiteTitle `
                    -Alias    $SiteAlias `
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
        [Parameter(Mandatory)][string]$TenantName,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertFolder,
        [Parameter(Mandatory)][string]$ApplicationName,
        [Parameter(Mandatory)][string]$SiteUrl
    )

    Write-Log "INFO" "Enabling external sharing on $SiteUrl"

    try {
        Connect-ProjectSharePoint `
            -Url             "https://$TenantName.sharepoint.com" `
            -TenantName      $TenantName `
            -ClientId        $ClientId `
            -CertFolder      $CertFolder `
            -ApplicationName $ApplicationName

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
        [Parameter(Mandatory)][string]$TenantName,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$CertFolder,
        [Parameter(Mandatory)][string]$ApplicationName,
        [Parameter(Mandatory)][string]$GroupId           # Entra group object ID
    )

    Write-Log "INFO" "Adding Entra group $GroupId as Members on $SiteUrl"

    try {
        Connect-ProjectSharePoint `
            -Url             $SiteUrl `
            -TenantName      $TenantName `
            -ClientId        $ClientId `
            -CertFolder      $CertFolder `
            -ApplicationName $ApplicationName

        $spMembers = Get-PnPGroup -AssociatedMemberGroup -ErrorAction Stop

        Add-PnPGroupMember -Group      $spMembers `
                           -LoginName  "c:0t.c|tenant|$GroupId" `
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
#   Config must include:
#     TenantName, ClientId, CertFolder, ApplicationName,
#     SiteAlias, SiteTitle, SiteUrl
# --------------------------------------------------------------------------
function Invoke-Step3-SharePoint {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$GroupId
    )

    Write-Log "STEP" "--- Step 3: SharePoint Site [$($Config.SiteTitle)] ---"

    # Splat shared connection params to avoid repeating them on every call
    $connParams = @{
        TenantName      = $Config.SPTenantName
        ClientId        = $Config.ClientId
        CertFolder      = $Config.CertFolder
        ApplicationName = $Config.ApplicationName
    }

    # Check if site already exists
    $existing = Get-SharePointSite -SiteUrl $Config.SiteUrl @connParams

    if ($existing) {
        Write-Log "SKIP" "Site '$($Config.SiteUrl)' already exists."
    } else {
        New-ProjectSharePointSite `
            -SiteAlias  $Config.SiteAlias `
            -SiteTitle  $Config.SiteTitle `
            -SiteUrl    $Config.SiteUrl `
            @connParams
    }

    # Always ensure sharing + membership are correct
    Set-SiteExternalSharing -SiteUrl $Config.SiteUrl @connParams
    Add-GroupAsSiteMembers  -SiteUrl $Config.SiteUrl -GroupId $GroupId @connParams

    Write-Log "SUCCESS" "Step 3 complete - site ready at $($Config.SiteUrl)"
    return [PSCustomObject]@{
        SiteUrl        = $Config.SiteUrl
        AlreadyExisted = [bool]$existing
    }
}
