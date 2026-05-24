# Entra Project Onboarding Script

Automates the full external-project onboarding workflow in Microsoft Entra ID + SharePoint.

## File Structure

```
External SharePoint Site/
├── main.ps1                     ← entry point (interactive wizard)
├── modules/
│   ├── auth.ps1                 ← Graph connection & required scopes
│   ├── config.ps1               ← project config & derived names
│   ├── logger.ps1               ← logging helpers
│   ├── step1-trusted-domain.ps1 ← cross-tenant access policy
│   ├── step2-entra-group.ps1    ← Entra security group
│   ├── step3-sharepoint.ps1     ← SharePoint site + members
│   ├── step4-entitlement.ps1    ← Entitlement Management access package
│   └── step5-lifecycle.ps1      ← Lifecycle workflow (welcome email)
└── logs/                        ← auto-created, one file per run
```

## Prerequisites

```powershell
Install-Module Microsoft.Graph           -Scope CurrentUser
Install-Module Microsoft.Graph.Beta      -Scope CurrentUser
Install-Module PnP.PowerShell            -Scope CurrentUser
```

## Required Graph Permissions

The script connects to Microsoft Graph and requests the following delegated scopes:

| Scope | Used by |
|-------|---------|
| `Policy.ReadWrite.CrossTenantAccess` | Step 1 |
| `CrossTenantInformation.ReadBasic.All` | Step 1 |
| `Group.ReadWrite.All` | Step 2 |
| `GroupMember.ReadWrite.All` | Step 2 |
| `Sites.FullControl.All` | Step 3 |
| `EntitlementManagement.ReadWrite.All` | Step 4 |
| `LifecycleWorkflows.ReadWrite.All` | Step 5 |
| `Directory.ReadWrite.All` | General |
| `Mail.Send` | General |

## Usage

### Full CLI (no prompts)

```powershell
.\main.ps1 -ProjectName "Acme Portal" `
           -ExternalDomain "acme.com" `
           -SPTenantName "contoso" `
           -PnPClientId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
           -ApproverEmail "approver@contoso.com" `
           -AccessDurationDays 90 `
           -CatalogName "SharePoint Groups for Externals"
```

### Interactive wizard (omit any or all parameters)

```powershell
.\main.ps1
```

Any parameter not supplied on the CLI will be prompted interactively:

| Parameter | Prompt | Example |
|-----------|--------|---------|
| `-ProjectName` | Project name | `Acme Portal` |
| `-ExternalDomain` | External organisation domain | `acme.com` |
| `-SPTenantName` | SharePoint tenant name | `contoso` (name only, not the full URL) |
| `-PnPClientId` | PnP app Client ID | Client ID of the Entra app registration used by PnP PowerShell (Step 3) |
| `-ApproverEmail` | Approver email | `approver@contoso.com` (resolved to ObjectId automatically) |
| `-AccessDurationDays` | Access duration (days) | `30`, `90`, `180`, or `360` |
| `-CatalogName` | Entitlement catalog name | Defaults to `SharePoint Groups for Externals` |

### Partial re-runs (step-skipping)

Use these flags when resuming after a partial failure. All other inputs are still collected interactively.

#### Skip trusted-domain step (already configured)
```powershell
.\main.ps1 -SkipStep1
```

#### Jump straight to SharePoint and onwards (group already exists)
```powershell
.\main.ps1 -StartFromStep 3 -GroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

#### Skip both group and site creation
```powershell
.\main.ps1 -SkipStep2 -GroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
           -SkipStep3 -SiteUrl "https://yourtenant.sharepoint.com/sites/ext-acme-portal"
```

#### Skip transcript logging
```powershell
.\main.ps1 -NoTranscript
```

## What Each Step Does

| Step | Action | API surface |
|------|--------|-------------|
| 1 | Resolves external domain → tenant ID, adds to Cross-Tenant Access Policy, configures inbound B2B trust (all users + all applications allowed) | `/v1.0/policies/crossTenantAccessPolicy` |
| 2 | Creates `sharepoint-ext-{project}-members` security group | `/v1.0/groups` |
| 3 | Creates a private SharePoint Team Site, enables external sharing (`ExternalUserAndGuestSharing`), adds the Entra group as site Members | PnP PowerShell |
| 4 | Finds or creates the entitlement catalog, creates an access package, adds the group as a Member resource role, creates an external-user request policy with a single internal approver and a configurable expiry (30/90/180/360 days) | `/v1.0/identityGovernance/entitlementManagement` |
| 5 | Creates a Lifecycle Workflow that triggers on group membership add and sends a welcome email with the SharePoint site link | `/beta/identityGovernance/lifecycleWorkflows` |

## Derived Resource Names

All resource names are computed automatically from the project name you enter:

| Resource | Pattern | Example (project = "Acme Portal") |
|----------|---------|-----------------------------------|
| Entra group | `sharepoint-ext-{safe-name}-members` | `sharepoint-ext-acme-portal-members` |
| SharePoint site URL | `https://{tenant}.sharepoint.com/sites/ext-{safe-name}` | `.../sites/ext-acme-portal` |
| Access package | `{ProjectName}` | `Acme Portal` |
| Lifecycle workflow | `Welcome - {ProjectName} external members` | `Welcome - Acme Portal external members` |

## Idempotency

Every step checks for existing resources before creating. Safe to re-run if something failed mid-way — already-created resources are skipped with a `SKIP` log line.

## Logs

Each run creates a timestamped transcript in `./logs/run-YYYYMMDD-HHmmss.log`.
Pass `-NoTranscript` to disable.
