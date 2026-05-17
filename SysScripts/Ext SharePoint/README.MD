# Entra Project Onboarding Script

Automates the full external-project onboarding workflow in Microsoft Entra ID + SharePoint.

## File Structure

```
entra-project-onboarding/
├── main.ps1                     ← entry point
├── modules/
│   ├── config.ps1               ← project config & derived names
│   ├── logger.ps1               ← logging + auth helpers
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
Install-Module PnP.PowerShell           -Scope CurrentUser
```

## Configuration

Before first run, open `main.ps1` and set the defaults, OR pass them as parameters:

| Parameter           | Description                                   |
|---------------------|-----------------------------------------------|
| `-SPAdminUrl`       | `https://yourtenant-admin.sharepoint.com`     |
| `-SPTenantUrl`      | `https://yourtenant.sharepoint.com`           |
| `-ApproverObjectId` | ObjectId of the internal user who approves    |
| `-CatalogName`      | Entitlement catalog name (default: "External Projects") |

## Usage Examples

### Full run (all 5 steps)
```powershell
.\main.ps1 -ProjectName "Acme Portal" -ExternalDomain "acme.com" `
           -ApproverObjectId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Skip trusted-domain step (already done)
```powershell
.\main.ps1 -ProjectName "Acme Portal" -ExternalDomain "acme.com" `
           -SkipStep1
```

### Jump straight to SharePoint + onwards (group already exists)
```powershell
.\main.ps1 -ProjectName "Acme Portal" -ExternalDomain "acme.com" `
           -StartFromStep 3 `
           -GroupId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Skip both group and site creation
```powershell
.\main.ps1 -ProjectName "Acme Portal" -ExternalDomain "acme.com" `
           -SkipStep2 -GroupId "..." `
           -SkipStep3 -SiteUrl "https://yourtenant.sharepoint.com/sites/proj-acme-portal" `
           -ApproverObjectId "..."
```

## What Each Step Does

| Step | Action | Graph/API surface |
|------|--------|-------------------|
| 1 | Resolves external domain → tenant ID, adds to Cross-Tenant Access Policy, configures inbound B2B trust | `/policies/crossTenantAccessPolicy` |
| 2 | Creates `sharepoint-ext-{project}-members` security group | `/groups` |
| 3 | Creates SharePoint team site, enables external sharing, adds group as Members | PnP PowerShell |
| 4 | Creates/finds Entitlement catalog, creates access package, adds group as resource, creates external-user request policy with internal approver | `/identityGovernance/entitlementManagement` |
| 5 | Creates Lifecycle Workflow: fires on group membership add → sends welcome email with site link | `/beta/identityGovernance/lifecycleWorkflows` |

## Idempotency

Every step checks for existing resources before creating. Safe to re-run if something failed mid-way — already-created resources are skipped with a `⏭️ SKIP` log line.

## Logs

Each run creates a timestamped transcript in `./logs/run-YYYYMMDD-HHmmss.log`.
Pass `-NoTranscript` to disable.

 