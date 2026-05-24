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

    # Title-case helper: capitalises first letter of each segment (split by hyphen or space)
    function ConvertTo-TitleCase ([string]$Text, [string]$Sep) {
        return ($Text -split $Sep | ForEach-Object {
            if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }
            else { $_ }
        }) -join $Sep
    }

    $safeTitle    = ConvertTo-TitleCase -Text $safe       -Sep '-'   # e.g. Acme-Portal
    $projectTitle = ConvertTo-TitleCase -Text $ProjectName -Sep ' '  # e.g. Acme Portal

    return [PSCustomObject]@{
        # Raw inputs
        ProjectName        = $ProjectName
        ExternalDomain     = $ExternalDomain.ToLower().Trim()

        # Derived names (single source of truth — URLs/aliases stay lowercase)
        GroupName          = "Sharepoint-Ext-$safeTitle-Members"
        GroupDescription   = "External Members For Project: $projectTitle"
        SiteName           = "External $safeTitle"
        SiteAlias          = "External $safe"
        SiteTitle          = "External $projectTitle"
        AccessPackageName  = "AccessPackage-Sharepoint-Ext-$safeTitle-Members"
        WorkflowName       = "Welcome - $projectTitle External Members"

        # SharePoint (derived from tenant name)
        SPTenantUrl        = "https://$tenantName.sharepoint.com"
        SPAdminUrl         = "https://$tenantName-admin.sharepoint.com"
        SiteUrl            = "https://$tenantName.sharepoint.com/sites/ext-$safe"
        TenantName         =  $tenantName
        # Entitlement / Lifecycle
        CatalogName        = $CatalogName
        ApproverObjectId   = $ApproverObjectId
        EmailSenderName    = $EmailSenderName
    }
}
