# =============================================================================
# modules/step4-entitlement.ps1
#
# Creates an Entitlement Management access package for the project:
#   - Finds or creates the catalog
#   - Creates the access package
#   - Adds the Entra group as a resource role
#   - Creates a policy allowing external users to request access
#     with an internal approver
#
# Graph API surfaces used:
#   /v1.0/identityGovernance/entitlementManagement/...
#
# Required scopes:
#   EntitlementManagement.ReadWrite.All
# =============================================================================

# --------------------------------------------------------------------------
# Get-OrNew-Catalog
# --------------------------------------------------------------------------
function Get-OrNew-Catalog {
    param([string]$CatalogName)

    $encoded = [Uri]::EscapeDataString($CatalogName)
    $uri     = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs?`$filter=displayName eq '$encoded'"
    $result  = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

    if ($result.value.Count -gt 0) {
        Write-Log "INFO" "Using existing catalog '$CatalogName' (id=$($result.value[0].id))"
        return $result.value[0].id
    }

    Write-Log "INFO" "Creating catalog '$CatalogName'..."
    $body    = @{ displayName = $CatalogName; description = "External project resources"; isExternallyVisible = $true } | ConvertTo-Json
    $catalog = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs" `
        -Body $body -ContentType "application/json" -ErrorAction Stop
    Write-Log "SUCCESS" "Catalog created (id=$($catalog.id))"
    return $catalog.id
}

# --------------------------------------------------------------------------
# Get-AccessPackageByName
# --------------------------------------------------------------------------
function Get-AccessPackageByName {
    param([string]$Name, [string]$CatalogId)
    $encoded = [Uri]::EscapeDataString($Name)
    $uri     = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq '$encoded' and catalog/id eq '$CatalogId'"
    $result  = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    if ($result.value.Count -gt 0) { return $result.value[0] }
    return $null
}

# --------------------------------------------------------------------------
# New-AccessPackage
# --------------------------------------------------------------------------
function New-AccessPackage {
    param([string]$Name, [string]$CatalogId)
    $body   = @{
        displayName = $Name
        description = "External access for project: $Name"
        isHidden    = $false
        catalog     = @{ id = $CatalogId }
    } | ConvertTo-Json
    $pkg = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages" `
        -Body $body -ContentType "application/json" -ErrorAction Stop
    Write-Log "SUCCESS" "Access package created (id=$($pkg.id))"
    return $pkg
}

# --------------------------------------------------------------------------
# Add-GroupResourceToPackage
#   Adds the Entra group as a "Member" resource role in the access package.
# --------------------------------------------------------------------------
function Add-GroupResourceToPackage {
    param([string]$PackageId, [string]$CatalogId, [string]$GroupId)

    Write-Log "INFO" "Adding group $GroupId as resource to access package..."

    # 1. Add group to catalog resources (idempotent - fails gracefully if exists)
    $addResourceBody = @{
        requestType = "adminAdd"
        resource    = @{
            originSystem = "AadGroup"
            originId     = $GroupId
        }
        catalog     = @{ id = $CatalogId }
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/resourceRequests" `
            -Body $addResourceBody -ContentType "application/json" -ErrorAction Stop | Out-Null
    } catch {
        $err = $_
        $e   = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($e.error.code -ne "Exists") { throw }

    }

    # 2+3. Get catalog resource with roles expanded in one call (avoids unreliable /roles sub-endpoint)
    $encoded  = [Uri]::EscapeDataString($GroupId)
    $resUri   = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/$CatalogId/resources?`$filter=originId eq '$encoded'&`$expand=roles,scopes"
    $resource   = $null
    $memberRole = $null
    $timeout    = 300; $elapsed = 0; $wait = 5
    do {
        Write-Log "INFO" "Waiting ${wait}s for catalog resource and roles to appear... (${elapsed}s elapsed)"
        Start-Sleep -Seconds $wait; $elapsed += $wait; $wait += 5
        $resource = (Invoke-MgGraphRequest -Method GET -Uri $resUri -ErrorAction Stop).value[0]
        if ($resource) {
            $memberRole = $resource.roles | Where-Object { $_.displayName -eq "Member" } | Select-Object -First 1
        }
    } while (-not $memberRole -and $elapsed -lt $timeout)

    if (-not $resource)   { throw "Catalog resource for group '$GroupId' did not appear after $timeout seconds." }
    if (-not $memberRole) { throw "Member role for catalog resource '$($resource.id)' did not appear after $timeout seconds." }
    Write-Log "INFO" "Catalog resource and Member role found (resourceId=$($resource.id), roleId=$($memberRole.id))"

    # 4. Create resource role scope on the package
    $scopeBody = @{
        role  = @{ id = $memberRole.id; displayName = $memberRole.displayName; originSystem = "AadGroup"; originId = $memberRole.originId }
        scope = @{ id = $resource.id; displayName = "All"; originSystem = "AadGroup"; originId = $GroupId; isRootScope = $true }
    } | ConvertTo-Json -Depth 5

    Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages/$PackageId/resourceRoleScopes" `
        -Body $scopeBody -ContentType "application/json" -ErrorAction Stop | Out-Null

    Write-Log "SUCCESS" "Group added as Member resource role in access package."
}

# --------------------------------------------------------------------------
# New-ExternalRequestPolicy
#   Policy: external users can request -> internal approver -> limited duration
#
#   AccessDurationDays: 30 | 90 | 180 | 360
#     The user's approved assignment expires automatically after this many days.
# --------------------------------------------------------------------------
function New-ExternalRequestPolicy {
    param(
        [string]$PackageId,
        [string]$ApproverObjectId,   # UPN or ObjectId of the internal approver
        [string]$PackageDisplayName,

        [ValidateSet(30, 90, 180, 360)]
        [int]$AccessDurationDays = 90
    )

    Write-Log "INFO" "Creating external request policy - duration: $AccessDurationDays days, approver: $ApproverObjectId"

    # ISO 8601 duration string (e.g. P90D)
    $isoDuration = "P${AccessDurationDays}D"

    $body = @{
        displayName  = "External request policy ($AccessDurationDays days)"
        description  = "External users may request access; internal approver required. Access expires after $AccessDurationDays days."
        allowedTargetScope = "allExternalUsers"
        specificAllowedTargets = @()
        expiration   = @{
            endDateTime = $null
            duration    = $isoDuration
            type        = "afterDuration"
        }
        requestorSettings = @{
            enableTargetsToSelfAddAccess  = $true
            enableTargetsToSelfUpdateAccess = $false
            enableTargetsToSelfRemoveAccess = $true
            allowCustomAssignmentSchedule   = $false
            enableOnBehalfRequestorsToAddAccess    = $false
            enableOnBehalfRequestorsToUpdateAccess = $false
            enableOnBehalfRequestorsToRemoveAccess = $false
        }
        requestApprovalSettings = @{
            isApprovalRequiredForAdd    = $true
            isApprovalRequiredForUpdate = $false
            stages = @(
                @{
                    durationBeforeAutomaticDenial = "P14D"
                    isApproverJustificationRequired = $false
                    isEscalationEnabled = $false
                    durationBeforeEscalation = "PT0S"
                    primaryApprovers = @(
                        @{
                            "@odata.type" = "#microsoft.graph.singleUser"
                            userId        = $ApproverObjectId
                        }
                    )
                    fallbackPrimaryApprovers = @()
                    escalationApprovers      = @()
                    fallbackEscalationApprovers = @()
                }
            )
        }
        questions = @(
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $false
                sequence          = 1
                isSingleLineQuestion = $true
                text = @{ defaultText = "Please enter your company name"; localizedTexts = @() }
                attributeName     = "companyName"
            }
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $false
                sequence          = 2
                isSingleLineQuestion = $true
                text = @{ defaultText = "Please enter your full name"; localizedTexts = @() }
                attributeName     = "displayName"
            }
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $false
                sequence          = 3
                isSingleLineQuestion = $true
                text = @{ defaultText = "Please enter your job title"; localizedTexts = @() }
                attributeName     = "jobTitle"
            }
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $false
                sequence          = 4
                isSingleLineQuestion = $true
                text = @{ defaultText = "Enter your work email address"; localizedTexts = @() }
                attributeName     = "mail"
            }
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $false
                sequence          = 5
                isSingleLineQuestion = $true
                text = @{ defaultText = "Enter your given name"; localizedTexts = @() }
                attributeName     = "givenName"
            }
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $true
                sequence          = 6
                isSingleLineQuestion = $true
                text = @{ defaultText = "Enter your surname"; localizedTexts = @() }
                attributeName     = "surname"
            }
            @{
                "@odata.type"     = "#microsoft.graph.accessPackageTextInputQuestion"
                isRequired        = $true
                isAnswerEditable  = $false
                sequence          = 7
                isSingleLineQuestion = $true
                text = @{ defaultText = "Enter your mobile phone number"; localizedTexts = @() }
                attributeName     = "mobilePhone"
            }
        )
        accessPackage = @{ id = $PackageId }
    } | ConvertTo-Json -Depth 10

    $policy = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" `
        -Body $body -ContentType "application/json" -ErrorAction Stop

    Write-Log "SUCCESS" "Assignment policy created (id=$($policy.id))"
    return $policy
}

# --------------------------------------------------------------------------
# Invoke-Step4-Entitlement                    <- main entry point for step 4
# --------------------------------------------------------------------------
function Invoke-Step4-Entitlement {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$GroupId,

        [ValidateSet(30, 90, 180, 360)]
        [int]$AccessDurationDays = 90
    )

    Write-Log "STEP" "--- Step 4: Entitlement Management [$($Config.AccessPackageName)] ---"

    if (-not $Config.ApproverObjectId) {
        throw "Config.ApproverObjectId is required for Step 4. Set it in New-ProjectConfig."
    }

    # Catalog
    $catalogId = Get-OrNew-Catalog -CatalogName $Config.CatalogName

    # Access Package (idempotent)
    $existing = Get-AccessPackageByName -Name $Config.AccessPackageName -CatalogId $catalogId
    if ($existing) {
        Write-Log "SKIP" "Access package '$($Config.AccessPackageName)' already exists (id=$($existing.id))."
        $packageId = $existing.id
    } else {
        $pkg = New-AccessPackage -Name $Config.AccessPackageName -CatalogId $catalogId
        $packageId = $pkg.id
    }

    # Resource role
    Add-GroupResourceToPackage -PackageId $packageId -CatalogId $catalogId -GroupId $GroupId

    # Request policy
    New-ExternalRequestPolicy `
        -PackageId          $packageId `
        -ApproverObjectId   $Config.ApproverObjectId `
        -PackageDisplayName $Config.AccessPackageName `
        -AccessDurationDays $AccessDurationDays

    Write-Log "SUCCESS" "Step 4 complete - access package '$($Config.AccessPackageName)' ready."
    return [PSCustomObject]@{ PackageId = $packageId; CatalogId = $catalogId }
}
 