# =============================================================================
# main.ps1
#
# Run with no arguments - the script prompts for everything interactively.
#
# Step-skipping flags (still available for partial re-runs):
#   .\main.ps1 -SkipStep1
#   .\main.ps1 -StartFromStep 3 -GroupId "..."
# =============================================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    # Step-skipping (optional - use when resuming a partial run)
    [ValidateRange(1,5)]
    [int]$StartFromStep = 1,

    [switch]$SkipStep1,
    [switch]$SkipStep2,
    [switch]$SkipStep3,
    [switch]$SkipStep4,
    [switch]$SkipStep5,

    # Pre-existing resource IDs when skipping creation steps
    [string]$GroupId  = "",
    [string]$SiteUrl  = "",

    [string]$LogDir   = "$PSScriptRoot\logs",
    [switch]$NoTranscript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load modules
$ModulesPath = Join-Path $PSScriptRoot "modules"
. "$ModulesPath\logger.ps1"
. "$ModulesPath\config.ps1"
. "$ModulesPath\auth.ps1"
. "$ModulesPath\step1-trusted-domain.ps1"
. "$ModulesPath\step2-entra-group.ps1"
. "$ModulesPath\step3-sharepoint.ps1"
. "$ModulesPath\step4-entitlement.ps1"
. "$ModulesPath\step5-lifecycle.ps1"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Read-NonEmpty {
    param([string]$Prompt)
    do {
        $value = (Read-Host $Prompt).Trim()
        if (-not $value) { Write-Host "  Value cannot be empty. Please try again." -ForegroundColor Yellow }
    } while (-not $value)
    return $value
}

function Read-Choice {
    param([string]$Prompt, [string[]]$Options)
    $display = $Options -join " / "
    do {
        $value = (Read-Host "$Prompt [$display]").Trim()
        if ($value -notin $Options) {
            Write-Host "  Invalid choice. Enter one of: $display" -ForegroundColor Yellow
        }
    } while ($value -notin $Options)
    return $value
}

function Resolve-UserEmailToId {
    param([string]$Email)
    Write-Log "INFO" "Resolving approver email to ObjectId ($Email)..."
    $encoded = [Uri]::EscapeDataString($Email)
    $uri     = "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$encoded' or mail eq '$encoded'&`$select=id,displayName,userPrincipalName"
    $result  = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    if ($result.value.Count -eq 0) {
        throw "No user found in Entra with email '$Email'. Check the address and try again."
    }
    $user = $result.value[0]
    Write-Log "SUCCESS" "Approver resolved: $($user.displayName) ($($user.userPrincipalName)) -> $($user.id)"
    return $user.id
}

function Build-SPAdminUrl {
    param([string]$TenantUrl)
    if ($TenantUrl -match '^(https://)([\w-]+)(\.sharepoint\.com.*)$') {
        return "$($Matches[1])$($Matches[2])-admin$($Matches[3])"
    }
    throw "Cannot derive admin URL from '$TenantUrl'. Expected format: https://<tenant>.sharepoint.com"
}

# ---------------------------------------------------------------------------
# Start transcript
# ---------------------------------------------------------------------------
if (-not $NoTranscript) { Start-RunLog -LogDir $LogDir }

try {
    # -----------------------------------------------------------------------
    # Interactive prompts
    # -----------------------------------------------------------------------
    Write-Host ""
    Write-Host "  ==========================================" -ForegroundColor Cyan
    Write-Host "   Entra Project Onboarding Wizard" -ForegroundColor Cyan
    Write-Host "  ==========================================" -ForegroundColor Cyan
    Write-Host ""

    $ProjectName      = Read-NonEmpty "Project name"
    $ExternalDomain   = Read-NonEmpty "External organisation domain (e.g. contoso.com)"
    $SPTenantUrl      = Read-NonEmpty "SharePoint tenant URL (e.g. https://yourtenant.sharepoint.com)"
    $SPAdminUrl       = Build-SPAdminUrl -TenantUrl $SPTenantUrl
    Write-Host "  -> SharePoint admin URL: $SPAdminUrl" -ForegroundColor DarkGray

    $ApproverEmail    = Read-NonEmpty "Approver email (internal user who approves access requests)"

    $durationChoice   = Read-Choice -Prompt "Access duration (days)" -Options @("30","90","180","360")
    $AccessDurationDays = [int]$durationChoice

    $CatalogName = (Read-Host "Entitlement catalog name [External Projects]").Trim()
    if (-not $CatalogName) { $CatalogName = "External Projects" }

    Write-Host ""

    # -----------------------------------------------------------------------
    Write-Log "STEP" "======================================================="
    Write-Log "STEP" " Project Onboarding: $ProjectName  /  $ExternalDomain"
    Write-Log "STEP" "======================================================="

    # Ensure required modules
    Assert-Module -Names @("Microsoft.Graph.Authentication", "Microsoft.Graph.Identity.SignIns",
                            "Microsoft.Graph.Groups", "PnP.PowerShell")

    # Connect to Graph (must happen before resolving approver)
    Connect-ProjectGraph

    # Resolve approver email to ObjectId
    $ApproverObjectId = Resolve-UserEmailToId -Email $ApproverEmail

    # Build config
    $config = New-ProjectConfig `
        -ProjectName       $ProjectName `
        -ExternalDomain    $ExternalDomain `
        -SPTenantUrl       $SPTenantUrl `
        -SPAdminUrl        $SPAdminUrl `
        -CatalogName       $CatalogName `
        -ApproverObjectId  $ApproverObjectId

    if ($SiteUrl) { $config.SiteUrl = $SiteUrl }

    Write-Log "INFO" "Group name  : $($config.GroupName)"
    Write-Log "INFO" "Site URL    : $($config.SiteUrl)"
    Write-Log "INFO" "Package name: $($config.AccessPackageName)"
    Write-Log "INFO" "Workflow    : $($config.WorkflowName)"
    Write-Log "INFO" "Duration    : $AccessDurationDays days"

    # Apply StartFromStep shortcut
    if ($StartFromStep -gt 1) {
        Write-Log "WARN" "StartFromStep=$StartFromStep - skipping steps 1 to $($StartFromStep-1)"
        if ($StartFromStep -gt 1) { $SkipStep1 = $true }
        if ($StartFromStep -gt 2) { $SkipStep2 = $true }
        if ($StartFromStep -gt 3) { $SkipStep3 = $true }
        if ($StartFromStep -gt 4) { $SkipStep4 = $true }
    }

    if ($SkipStep2 -and -not $GroupId) {
        throw "-GroupId is required when -SkipStep2 is set (or StartFromStep > 2)."
    }

    # -----------------------------------------------------------------------
    # Step 1 - Trusted domain
    # -----------------------------------------------------------------------
    if (-not $SkipStep1) {
        $step1Result = Invoke-Step1-TrustedDomain -Config $config
    } else {
        Write-Log "SKIP" "Step 1 skipped (trusted domain)."
        $step1Result = $null
    }

    # -----------------------------------------------------------------------
    # Step 2 - Entra group
    # -----------------------------------------------------------------------
    if (-not $SkipStep2) {
        $step2Result = Invoke-Step2-EntraGroup -Config $config
        $GroupId     = $step2Result.GroupId
    } else {
        Write-Log "SKIP" "Step 2 skipped (Entra group). Using GroupId=$GroupId"
        $step2Result = [PSCustomObject]@{ GroupId = $GroupId; AlreadyExisted = $true }
    }

    # -----------------------------------------------------------------------
    # Step 3 - SharePoint site
    # -----------------------------------------------------------------------
    if (-not $SkipStep3) {
        $step3Result = Invoke-Step3-SharePoint -Config $config -GroupId $GroupId
    } else {
        Write-Log "SKIP" "Step 3 skipped (SharePoint site). Using URL=$($config.SiteUrl)"
        $step3Result = [PSCustomObject]@{ SiteUrl = $config.SiteUrl; AlreadyExisted = $true }
    }

    # -----------------------------------------------------------------------
    # Step 4 - Entitlement management
    # -----------------------------------------------------------------------
    if (-not $SkipStep4) {
        $step4Result = Invoke-Step4-Entitlement -Config $config -GroupId $GroupId -AccessDurationDays $AccessDurationDays
    } else {
        Write-Log "SKIP" "Step 4 skipped (Entitlement management)."
        $step4Result = $null
    }

    # -----------------------------------------------------------------------
    # Step 5 - Lifecycle workflow
    # -----------------------------------------------------------------------
    if (-not $SkipStep5) {
        $step5Result = Invoke-Step5-LifecycleWorkflow -Config $config -GroupId $GroupId
    } else {
        Write-Log "SKIP" "Step 5 skipped (Lifecycle workflow)."
        $step5Result = $null
    }

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    Write-Log "STEP" "========================= SUMMARY ========================"
    Write-Log "SUCCESS" "Project        : $ProjectName"
    Write-Log "SUCCESS" "External domain: $ExternalDomain"
    Write-Log "SUCCESS" "Entra group    : $($config.GroupName) (id=$GroupId)"
    Write-Log "SUCCESS" "SharePoint site: $($config.SiteUrl)"
    Write-Log "SUCCESS" "Approver       : $ApproverEmail (id=$ApproverObjectId)"
    Write-Log "SUCCESS" "Access duration: $AccessDurationDays days"
    if ($step4Result) {
        Write-Log "SUCCESS" "Access package : $($config.AccessPackageName) (id=$($step4Result.PackageId))"
    }
    if ($step5Result) {
        Write-Log "SUCCESS" "LCW workflow   : $($config.WorkflowName) (id=$($step5Result.WorkflowId))"
    }
    Write-Log "STEP" "=========================================================="
}
catch {
    Write-Log "ERROR" "Fatal error: $_"
    Write-Log "ERROR" $_.ScriptStackTrace
    exit 1
}
finally {
    if (-not $NoTranscript) { Stop-RunLog }
}
 