# =============================================================================
# modules/config.ps1
# Central configuration. Edit the variables in the CONFIG block below.
# All project-derived names are computed here so every other module can
# import this file and use $Config.* without hard-coding strings.
# =============================================================================

function New-ProjectConfig {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,

        [Parameter(Mandatory)]
        [string]$ExternalDomain,

        [Parameter(Mandatory)]
        [string]$SPTenantUrl,

        # Derived automatically if not supplied
        [string]$SPAdminUrl     = "",

        # --- Entitlement Management ---
        # Resource catalog to attach the access package to (leave empty to auto-create)
        [string]$CatalogName    = "External Projects",

        # Internal user or group ObjectId that approves access requests
        [string]$ApproverObjectId = "",   # <-- fill before running step 4

        # --- Lifecycle Workflow ---
        # Sender display name used in the welcome e-mail
        [string]$EmailSenderName = "IT Operations"
    )

    $safe = $ProjectName.ToLower() -replace '[^a-z0-9\-]', '-'

    # Derive admin URL from tenant URL if not explicitly supplied
    if (-not $SPAdminUrl) {
        if ($SPTenantUrl -match '^(https://)([\w-]+)(\.sharepoint\.com.*)$') {
            $SPAdminUrl = "$($Matches[1])$($Matches[2])-admin$($Matches[3])"
        } else {
            throw "Cannot derive SPAdminUrl from '$SPTenantUrl'. Expected: https://<tenant>.sharepoint.com"
        }
    }

    return [PSCustomObject]@{
        # Raw inputs
        ProjectName        = $ProjectName
        ExternalDomain     = $ExternalDomain.ToLower().Trim()

        # Derived names (single source of truth)
        GroupName          = "sharepoint-ext-$safe-members"
        GroupDescription   = "External members for project: $ProjectName"
        SiteName           = "proj-$safe"
        SiteAlias          = "proj-$safe"
        SiteTitle          = "Project $ProjectName"
        AccessPackageName  = $ProjectName
        WorkflowName       = "Welcome - $ProjectName external members"

        # SharePoint
        SPAdminUrl         = $SPAdminUrl
        SPTenantUrl        = $SPTenantUrl
        SiteUrl            = "$SPTenantUrl/sites/proj-$safe"

        # Entitlement / Lifecycle
        CatalogName        = $CatalogName
        ApproverObjectId   = $ApproverObjectId
        EmailSenderName    = $EmailSenderName
    }
}
 