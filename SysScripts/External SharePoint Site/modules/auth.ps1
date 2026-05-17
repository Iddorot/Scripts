
# =============================================================================
# modules/auth.ps1
# Connects to Microsoft Graph with all required scopes.
# Split into its own function so main.ps1 can call it once and every
# module reuses the existing session.
# =============================================================================

$RequiredScopes = @(
    # Step 1 - cross-tenant access policy
    "Policy.ReadWrite.CrossTenantAccess"
    "CrossTenantInformation.ReadBasic.All"

    # Step 2 - groups
    "Group.ReadWrite.All"
    "GroupMember.ReadWrite.All"

    # Step 3 - SharePoint (via Graph + PnP)
    "Sites.FullControl.All"

    # Step 4 - entitlement management
    "EntitlementManagement.ReadWrite.All"

    # Step 5 - lifecycle workflows
    "LifecycleWorkflows.ReadWrite.All"

    # General
    "Directory.ReadWrite.All"
    "Mail.Send"
)

function Connect-ProjectGraph {

    Write-Log "STEP" "Connecting to Microsoft Graph..."

    try {
        # Check if already connected with the right scopes
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($ctx) {
            $missing = $RequiredScopes | Where-Object { $_ -notin $ctx.Scopes }
            if ($missing.Count -eq 0) {
                Write-Log "SUCCESS" "Already connected as $($ctx.Account)"
                return
            }
            Write-Log "WARN" "Re-connecting - missing scopes: $($missing -join ', ')"
        }

        $connectParams = @{ Scopes = $RequiredScopes }
        Connect-MgGraph @connectParams -NoWelcome
        Write-Log "SUCCESS" "Connected as $((Get-MgContext).Account)"
    }
    catch {
        Write-Log "ERROR" "Graph connection failed: $_"
        throw
    }
}