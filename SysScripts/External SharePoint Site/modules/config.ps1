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
        # Just the tenant name, e.g. "contoso" (not the full URL)
        [string]$SPTenantName,

        # --- Entitlement Management ---
        # Resource catalog to attach the access package to (leave empty to auto-create)
        [string]$CatalogName    = "SharePoint Groups for Externals",

        # Internal user or group ObjectId that approves access requests
        [string]$ApproverObjectId = "",   # <-- fill before running step 4

        # --- Lifecycle Workflow ---
        # Sender display name used in the welcome e-mail
        [string]$EmailSenderName = "IT Operations"
    )

    $safe       = $ProjectName.ToLower() -replace '[^a-z0-9\-]', '-'
    $tenantName = $SPTenantName.ToLower().Trim()

    return [PSCustomObject]@{
        # Raw inputs
        ProjectName        = $ProjectName
        ExternalDomain     = $ExternalDomain.ToLower().Trim()

        # Derived names (single source of truth)
        GroupName          = "sharepoint-ext-$safe-members"
        GroupDescription   = "External members for project: $ProjectName"
        SiteName           = "External $safe"
        SiteAlias          = "External $safe"
        SiteTitle          = "External $ProjectName"
        AccessPackageName  = $ProjectName
        WorkflowName       = "Welcome - $ProjectName external members"

        # SharePoint (derived from tenant name)
        SPTenantUrl        = "https://$tenantName.sharepoint.com"
        SPAdminUrl         = "https://$tenantName-admin.sharepoint.com"
        SiteUrl            = "https://$tenantName.sharepoint.com/sites/ext-$safe"

        # Entitlement / Lifecycle
        CatalogName        = $CatalogName
        ApproverObjectId   = $ApproverObjectId
        EmailSenderName    = $EmailSenderName
    }
}
