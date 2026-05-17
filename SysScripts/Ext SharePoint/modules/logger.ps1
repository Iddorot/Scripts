# =============================================================================
# modules/logger.ps1
# Coloured, levelled console logging with optional transcript file.
# =============================================================================

$script:TranscriptPath = $null

function Start-RunLog {
    param([string]$LogDir = "$PSScriptRoot\..\logs")
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $ts  = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:TranscriptPath = Join-Path $LogDir "run-$ts.log"
    Start-Transcript -Path $script:TranscriptPath -Append | Out-Null
    Write-Log "INFO" "Transcript started -> $($script:TranscriptPath)"
}

function Stop-RunLog {
    if ($script:TranscriptPath) {
        Stop-Transcript | Out-Null
        Write-Log "INFO" "Transcript saved -> $($script:TranscriptPath)"
    }
}

function Write-Log {
    param(
        [ValidateSet("INFO","SUCCESS","WARN","ERROR","STEP","SKIP","DEBUG")]
        [string]$Level = "INFO",
        [string]$Message
    )

    $stamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "Cyan"    }
        "SUCCESS" { "Green"   }
        "WARN"    { "Yellow"  }
        "ERROR"   { "Red"     }
        "STEP"    { "Magenta" }
        "SKIP"    { "DarkGray"}
        "DEBUG"   { "Gray"    }
    }

    $prefix = switch ($Level) {
        "INFO"    { "[i] " }
        "SUCCESS" { "[OK] " }
        "WARN"    { "[!!] " }
        "ERROR"   { "[ERR] " }
        "STEP"    { ">? " }
        "SKIP"    { ">>? " }
        "DEBUG"   { "[..] " }
    }

    Write-Host "$stamp  $prefix[$Level]  $Message" -ForegroundColor $color
}

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
    param(
        [string]$TenantId = $env:ENTRA_TENANT_ID   # or hard-code your tenant GUID
    )

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
        if ($TenantId) { $connectParams["TenantId"] = $TenantId }

        Connect-MgGraph @connectParams -NoWelcome
        Write-Log "SUCCESS" "Connected as $((Get-MgContext).Account)"
    }
    catch {
        Write-Log "ERROR" "Graph connection failed: $_"
        throw
    }
}

function Assert-Module {
    param([string[]]$Names)
    foreach ($name in $Names) {
        if (-not (Get-Module -ListAvailable -Name $name)) {
            Write-Log "WARN" "Module '$name' not found - installing..."
            Install-Module $name -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module $name -ErrorAction Stop
    }
}
 