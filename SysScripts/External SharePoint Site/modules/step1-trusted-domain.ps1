# =============================================================================
# modules/step1-trusted-domain.ps1
# =============================================================================

function Resolve-ExternalTenantId {
    param(
        [Parameter(Mandatory)][string]$Domain
    )

    Write-Log "INFO" "Resolving tenant for domain: $Domain"

    try {
        $uri      = "https://graph.microsoft.com/v1.0/tenantRelationships/findTenantInformationByDomainName(domainName='$Domain')"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

        Write-Log "SUCCESS" "Resolved -> TenantId=$($response.tenantId)  DisplayName=$($response.displayName)"
        return $response.tenantId
    }
    catch {
        $err  = $_
        $body = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($body.error.code -eq "Request_ResourceNotFound") {
            Write-Log "ERROR" "Domain '$Domain' could not be resolved to an Entra tenant."
            Write-Log "WARN"  "Possible reasons: domain not registered in Azure AD, or a consumer/non-Entra tenant."
        } else {
            Write-Log "ERROR" "Tenant lookup failed: $($body.error.message) $err"
        }
        throw
    }
}

function Get-CrossTenantPartner {
    param(
        [Parameter(Mandatory)][string]$TenantId
    )

    try {
        $uri    = "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/$TenantId"
        $result = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        return $result
    }
    catch {
        $err  = $_
        $body = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($body.error.code -in @("Request_ResourceNotFound", "ResourceNotFound")) {
            return $null
        }
        Write-Log "ERROR" "Error checking cross-tenant partner: $($body.error.message) $err"
        throw
    }
}

function Add-CrossTenantPartner {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$Domain
    )

    Write-Log "INFO" "Creating cross-tenant access partner for $Domain ($TenantId)"

    $body = @{
        tenantId = $TenantId
    } | ConvertTo-Json

    try {
        $uri    = "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners"
        $result = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Log "SUCCESS" "Partner entry created for tenant $TenantId"
        return $result
    }
    catch {
        $err     = $_
        $errBody = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        Write-Log "ERROR" "Failed to create partner: $($errBody.error.message) $err"
        throw
    }
}

function Set-CrossTenantTrustSettings {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [bool]$TrustMfa              = $false,
        [bool]$TrustCompliantDevices = $false,
        [bool]$TrustHybridDevices    = $false
    )

    Write-Log "INFO" "Configuring inbound B2B collaboration trust for tenant $TenantId"

    $inboundTrust = @{
        isMfaAccepted                       = $TrustMfa
        isCompliantDeviceAccepted           = $TrustCompliantDevices
        isHybridAzureADJoinedDeviceAccepted = $TrustHybridDevices
    }

    $b2bCollab = @{
        inboundTrust            = $inboundTrust
        b2bCollaborationInbound = @{
            usersAndGroups = @{
                accessType = "allowed"
                targets    = @(
                    @{ target = "AllUsers"; targetType = "user" }
                )
            }
            applications = @{
                accessType = "allowed"
                targets    = @(
                    @{ target = "AllApplications"; targetType = "application" }
                )
            }
        }
    }

    $body = $b2bCollab | ConvertTo-Json -Depth 10

    try {
        $uri = "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/$TenantId"
        Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Log "SUCCESS" "Trust settings applied (MFA=$TrustMfa, Compliant=$TrustCompliantDevices)"
    }
    catch {
        $err     = $_
        $errBody = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        Write-Log "ERROR" "Failed to patch trust settings: $($errBody.error.message) $err"
        throw
    }
}

function Invoke-Step1-TrustedDomain {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config
    )

    $domain = $Config.ExternalDomain
    Write-Log "STEP" "--- Step 1: Trusted Domain [$domain] ---"

    $tenantId = Resolve-ExternalTenantId -Domain $domain
    $existing = Get-CrossTenantPartner -TenantId $tenantId

    if ($existing) {
        Write-Log "SKIP" "Domain '$domain' (tenant $tenantId) is already in cross-tenant access policy."
        Write-Log "INFO" "Re-applying trust settings to ensure they are correct..."
        Set-CrossTenantTrustSettings -TenantId $tenantId `
            -TrustMfa $false -TrustCompliantDevices $false -TrustHybridDevices $false

        return [PSCustomObject]@{ TenantId = $tenantId; AlreadyExisted = $true }
    }

    Add-CrossTenantPartner -TenantId $tenantId -Domain $domain
    Set-CrossTenantTrustSettings -TenantId $tenantId `
        -TrustMfa $false -TrustCompliantDevices $false -TrustHybridDevices $false

    Write-Log "SUCCESS" "Step 1 complete - domain '$domain' is now a trusted partner."
    return [PSCustomObject]@{ TenantId = $tenantId; AlreadyExisted = $false }
}