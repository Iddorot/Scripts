# =============================================================================
# modules/step5-lifecycle.ps1
#
# Creates an Entra ID Governance Lifecycle Workflow that fires when a user
# is added to the project group and sends them a welcome e-mail containing
# the SharePoint site link.
#
# Trigger: onDemand + group membership change -> send email task
#
# Graph API:
#   POST /beta/identityGovernance/lifecycleWorkflows/workflows
#
# Required scopes:
#   LifecycleWorkflows.ReadWrite.All
# =============================================================================

# --------------------------------------------------------------------------
# Get-LifecycleWorkflowByName
# --------------------------------------------------------------------------
function Get-LifecycleWorkflowByName {
    param([string]$WorkflowName)

    $encoded = [Uri]::EscapeDataString($WorkflowName)
    $uri     = "https://graph.microsoft.com/beta/identityGovernance/lifecycleWorkflows/workflows?`$filter=displayName eq '$encoded'&`$select=id,displayName,isEnabled"
    $result  = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    if ($result.value.Count -gt 0) { return $result.value[0] }
    return $null
}

# --------------------------------------------------------------------------
# New-WelcomeEmailWorkflow
#   Creates a lifecycle workflow triggered when a user is added to the
#   specified group. Sends a welcome e-mail with the site URL.
# --------------------------------------------------------------------------
function New-WelcomeEmailWorkflow {
    param(
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$ProjectName,
        [string]$SenderDisplayName = "IT Operations"
    )

    Write-Log "INFO" "Creating lifecycle workflow: $WorkflowName"

    $emailSubject = "Welcome to the $ProjectName project workspace"
    $emailBody    = @"
<html><body>
<p>Hi {{userDisplayName}},</p>
<p>You have been added to the <strong>$ProjectName</strong> project collaboration space.</p>
<p>Access the SharePoint site here:</p>
<p><a href="$SiteUrl">$ProjectName SharePoint Site</a></p>
<p>If you have any questions, please contact your project lead.</p>


<p>$SenderDisplayName</p>
</body></html>
"@

    # Lifecycle Workflows use the /beta endpoint (GA is pending)
    $body = @{
        displayName  = $WorkflowName
        description  = "Sends a welcome email when a user is added to the $ProjectName group."
        isEnabled    = $true
        isSchedulingEnabled = $false   # trigger manually or via membership event

        # Trigger: when a user is added to the group
        executionConditions = @{
            "@odata.type" = "#microsoft.graph.identityGovernance.membershipChangeTrigger"
            triggerType   = "groupMembershipChange"
            groupId       = $GroupId
            membershipChangeType = "add"
        }

        tasks = @(
            @{
                continueOnError = $false
                description     = "Send welcome email to new external member"
                displayName     = "Send welcome email"
                isEnabled       = $true
                taskDefinitionId = "70b29d51-b59a-4773-9280-8841dfd3f2ea"  # built-in: send email
                arguments       = @(
                    @{ name = "subject";          value = $emailSubject }
                    @{ name = "body";             value = $emailBody    }
                    @{ name = "messageLanguage";  value = "en-US"       }
                    @{ name = "carbonCopyRecipients"; value = "" }
                )
            }
        )
    } | ConvertTo-Json -Depth 10

    try {
        $wf = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/beta/identityGovernance/lifecycleWorkflows/workflows" `
            -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Log "SUCCESS" "Lifecycle workflow created (id=$($wf.id))"
        return $wf
    }
    catch {
        $err     = $_
        $errBody = $err.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        Write-Log "ERROR" "Failed to create lifecycle workflow: $($errBody.error.message) $err"
        throw
    }
}

# --------------------------------------------------------------------------
# Invoke-Step5-LifecycleWorkflow              <- main entry point for step 5
# --------------------------------------------------------------------------
function Invoke-Step5-LifecycleWorkflow {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Config,
        [Parameter(Mandatory)][string]$GroupId
    )

    Write-Log "STEP" "--- Step 5: Lifecycle Workflow [$($Config.WorkflowName)] ---"

    $existing = Get-LifecycleWorkflowByName -WorkflowName $Config.WorkflowName

    if ($existing) {
        Write-Log "SKIP" "Workflow '$($Config.WorkflowName)' already exists (id=$($existing.id))."
        return [PSCustomObject]@{ WorkflowId = $existing.id; AlreadyExisted = $true }
    }

    $wf = New-WelcomeEmailWorkflow `
        -WorkflowName       $Config.WorkflowName `
        -GroupId            $GroupId `
        -SiteUrl            $Config.SiteUrl `
        -ProjectName        $Config.ProjectName `
        -SenderDisplayName  $Config.EmailSenderName

    Write-Log "SUCCESS" "Step 5 complete - workflow active, watching group $GroupId"
    return [PSCustomObject]@{ WorkflowId = $wf.id; AlreadyExisted = $false }
}