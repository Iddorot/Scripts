# =============================================================================
# modules/step1-trusted-domain.ps1
# =============================================================================

function Get-GraphErrorBody {
    param([object]$Err)
    $raw = $Err.ErrorDetails.Message
    if ($raw -match '(\{.*\})') {
        return $Matches[1] | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    return $null
}

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
        $body = Get-GraphErrorBody -Err $_
        if ($body.error.code -eq "Request_ResourceNotFound") {
            Write-Log "ERROR" "Domain '$Domain' could not be resolved to an Entra tenant."
            Write-Log "WARN"  "Possible reasons: domain not registered in Azure AD, or a consumer/non-Entra tenant."
        } else {
            Write-Log "ERROR" "Tenant lookup failed: $($body.error.message) $_"
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
        $body = Get-GraphErrorBody -Err $_
        if ($body.error.code -in @("Request_ResourceNotFound", "ResourceNotFound", "Directory_ObjectNotFound") `
            -or $_.Exception.Message -match "404") {
            return $null
        }
        Write-Log "ERROR" "Error checking cross-tenant partner: $($body.error.message) $_"
        throw
    }
}

function Add-CrossTenantPartner {
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$Domain
    )

    Write-Log "INFO" "Creating cross-tenant access partner for $Domain ($TenantId)"

    $body = @{ tenantId = $TenantId } | ConvertTo-Json

    try {
        $uri    = "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners"
        $result = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Log "SUCCESS" "Partner entry created for tenant $TenantId"
        return $result
    }
    catch {
        $body = Get-GraphErrorBody -Err $_
        Write-Log "ERROR" "Failed to create partner: $($body.error.message) $_"
        throw
    }
}

function Set-CrossTenantTrustSettings {
    param(
        [Parameter(Mandatory)][string]$TenantId
    )

    Write-Log "INFO" "Configuring inbound B2B collaboration trust for tenant $TenantId"

    $body = @{
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
    } | ConvertTo-Json -Depth 10

    try {
        $uri = "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/$TenantId"
        Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Log "SUCCESS" "Trust settings applied"
    }
    catch {
        $errBody = Get-GraphErrorBody -Err $_
        Write-Log "ERROR" "Failed to patch trust settings: $($errBody.error.message) $_"
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
        Set-CrossTenantTrustSettings -TenantId $tenantId
        return [PSCustomObject]@{ TenantId = $tenantId; AlreadyExisted = $true }
    }

    Add-CrossTenantPartner -TenantId $tenantId -Domain $domain
    Set-CrossTenantTrustSettings -TenantId $tenantId

    Write-Log "SUCCESS" "Step 1 complete - domain '$domain' is now a trusted partner."
    return [PSCustomObject]@{ TenantId = $tenantId; AlreadyExisted = $false }
}
