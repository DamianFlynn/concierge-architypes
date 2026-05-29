# concierge-architypes

IaC scaffold templates for [Innofactor Concierge](https://github.com/InnofactorOrg/concierge-app) — the automated Azure landing zone provisioner.

When Concierge provisions a new Azure spoke, it downloads a template from this repository, substitutes environment-specific tokens, and commits the result to the new spoke's Git repository as the starting point for infrastructure-as-code.

This repository defines what every new customer environment looks like on day one.

---

## How Concierge uses this repository

The `ArchitypesUri` application setting in the Concierge Function App points to the raw content base URL of this repository:

```
https://raw.githubusercontent.com/DamianFlynn/concierge-architypes/main
```

When the `dfa_NewSpoke05ConfigureSpoke` activity function runs, it constructs a download URL by appending the architype name and format suffix to this base URL. The file is fetched with no authentication — this repository is public.

**URL resolution — format fallback order:**

For an architype named `network`, Concierge tries these URLs in order and uses the first one that returns HTTP 200:

| Priority | URL | IaC type |
|---|---|---|
| 1 (default) | `{ArchitypesUri}/network.json` | ARM / Azure-Deploy |
| 2 (fallback) | `{ArchitypesUri}/network.bicep` | Bicep / AVM |
| 3 (fallback) | `{ArchitypesUri}/network/main.tf` | Terraform |

For Terraform, Concierge fetches two files from the subdirectory: `network/main.tf` (the root module) and `network/main.auto.tfvars` (variable defaults with token placeholders).

The `DefaultArchitype` application setting controls which architype name Concierge uses when the provisioning request does not specify one. The current default is `network`.

---

## Token substitution

After downloading the template, Concierge replaces every `[#_token_#]` placeholder with a provisioning-time value before committing the result to the new spoke repository. The substitution is a simple string replacement — every occurrence of each token is replaced globally.

The committed file has no remaining `[#_token_#]` placeholders and is immediately deployable.

**Complete token table:**

| Token | Substituted with | Example value | Source |
|---|---|---|---|
| `[#_service.subscription.id_#]` | New subscription GUID | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` | Returned by subscription creation step |
| `[#_service.name_#]` | Normalised service name | `salgsl` | Request field `Service` (1–6 lowercase alphanumeric chars) |
| `[#_service.environment_#]` | Environment prefix | `t` | Request field `Environment` (`t` = test, `p` = production) |
| `[#_service.project_#]` | Project / service display name | `salgsl` | Same as service name in current implementation |
| `[#_service.vnet.cidr_#]` | Computed VNet CIDR block | `10.162.0.0/25` | Allocated from `SuperNet` + `DefaultVnetCIDR` app setting |
| `[#_service.vnet.subnet.cidr_#]` | Computed subnet CIDR block | `10.162.0.0/26` | Sub-divided from VNet CIDR + `DefaultVnetSubnetCIDR` app setting |
| `[#_service.deployclient.id_#]` | Azure-Deploy container image reference | `innofactorazuredeploy.azurecr.io/azuredeploy:3.0.10` | `DeployContainerAddress` app setting |
| `[#_service.settings.repo_#]` | Deployment secrets repository name | `innofactor-datacenter-secrets` | `DefaultSettingsRepoName` app setting |
| `[#_service.deploy.variablegroup_#]` | ADO variable group name | `Concierge-Secrets` | `DefaultDeployVariableGroupName` app setting |

Tokens not present in a template file are ignored — use only the tokens your IaC needs.

**Example — before and after substitution for a `t-salgsl` provisioning run:**

Before (raw template):
```json
{
  "subscriptionId": "[#_service.subscription.id_#]",
  "environment": "[#_service.environment_#]",
  "serviceName": "[#_service.name_#]",
  "vnetCidr": "[#_service.vnet.cidr_#]"
}
```

After (committed to spoke repository):
```json
{
  "subscriptionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "environment": "t",
  "serviceName": "salgsl",
  "vnetCidr": "10.162.0.0/25"
}
```

---

## Available architypes

### `network` — VNet-based spoke (default)

Provisions a standard Azure network landing zone: resource group, VNet (configurable CIDR), NSG attached to `PeFrontendSubnet`, two subnets (`PeFrontendSubnet` with private endpoint network policies disabled, `ScalableSubnet` delegated to `Microsoft.App/environments`), and standard Innofactor tags (`Environment`, `Service`, `ManagedBy`).

All three formats provision the same logical topology. Choose the format that matches your spoke's IaC toolchain.

| Format | File(s) | Status |
|---|---|---|
| ARM / Azure-Deploy | `network.json` | Available |
| Bicep / AVM | `network.bicep` | Available |
| Terraform | `network/main.tf` + `network/main.auto.tfvars` | Available |

**`network.json` — ARM / Azure-Deploy format**

Uses the Azure-Deploy engine (`innofactorazuredeploy.azurecr.io/azuredeploy`). Defines a resource group, NSG, and VNet with both subnets. The `dependActions` block resolves the NSG resource ID into the VNet subnet config at deploy time. VNet address space and subnet prefixes are set via the `replaceStrings` map in the template header.

**`network.bicep` — Bicep / AVM format**

`targetScope = 'subscription'`. Uses public Azure Verified Modules: `br/public:network/network-security-group:1.0.0` and `br/public:network/virtual-network:1.1.3`. Parameters are typed with defaults — Concierge passes `environment` and `serviceName` as the two required parameters.

**`network/main.tf` — Terraform format**

Uses `hashicorp/azurerm ~> 3.0` with an `azurerm` backend (configured externally). The `main.auto.tfvars` file is committed alongside `main.tf`; Concierge substitutes the `[#_token_#]` placeholders in `main.auto.tfvars` before committing. Terraform reads the `.auto.tfvars` file automatically — no `-var-file` flag needed.

---

## CI scaffolding — design intent

> **Status: planned.** CI scaffolding files will be added to each architype once Concierge end-to-end smoke tests pass. This section documents the intended design so contributors know what to build.

Concierge commits the IaC template to the new spoke repository and then triggers the first CI/CD pipeline run (`dfa_NewSpoke06Workflow`). For that pipeline run to succeed, the repository must contain CI configuration appropriate to the IaC type and the target Git platform.

Concierge supports both Azure DevOps and GitHub as spoke repository hosts. CI scaffolding must work on both.

### CI system selection

| IaC type | CI system | ADO support | GitHub support | Notes |
|---|---|---|---|---|
| Terraform | Atlantis | Atlantis monitors ADO repos via webhook | Atlantis monitors GitHub repos via webhook | Single CI system serves both platforms |
| Bicep | bicep-action | `azure-pipelines.yml` referencing `InnofactorOrg/bicep-action` templates | `.github/workflows/deploy.yml` using bicep-action reusable workflow | Separate files per platform |
| ARM / Azure-Deploy | Azure-Deploy container | ADO pipeline only | Not planned | Deprecated — see note below |

### Terraform → Atlantis

Terraform spokes get an `atlantis.yaml` at the repository root. The Innofactor Atlantis server (`atlantis.elmeragroup.no`) monitors both ADO and GitHub repositories for pull requests via webhook. `terraform plan` runs on every PR; `terraform apply` runs on merge. No additional CI configuration is required — Atlantis handles both platforms from one file.

The committed `atlantis.yaml` scaffold (with token substitution applied):

```yaml
version: 3
projects:
  - name: [#_service.name_#]-[#_service.environment_#]
    dir: .
    terraform_version: v1.x
    autoplan:
      when_modified: ["*.tf", "*.tfvars", "*.auto.tfvars"]
      enabled: true
    apply_requirements:
      - approved
```

### Bicep → bicep-action

Bicep spokes get CI configuration using the `InnofactorOrg/bicep-action` shared pipeline templates. These provide `plan` (WhatIf) and `deploy` stages with OIDC authentication and environment gates.

**Azure DevOps (`azure-pipelines.yml`):**

```yaml
# Scaffolded by Concierge — [#_service.name_#]-[#_service.environment_#]
trigger:
  branches: { include: [main] }
  paths: { include: ['**/*.bicep', '**/*.bicepparam'] }

resources:
  repositories:
    - repository: bicep-action
      type: github
      name: InnofactorOrg/bicep-action
      ref: refs/heads/main
      endpoint: GitHub-InnofactorOrg

stages:
  - template: .azuredevops/templates/plan-stage.yml@bicep-action
    parameters:
      environmentName: [#_service.environment_#]-[#_service.name_#]
      templateFile: main.bicep
      parametersFile: environments/[#_service.environment_#].bicepparam
  - template: .azuredevops/templates/deploy-stage.yml@bicep-action
    parameters:
      environmentName: [#_service.environment_#]-[#_service.name_#]
      templateFile: main.bicep
      parametersFile: environments/[#_service.environment_#].bicepparam
```

**GitHub Actions (`.github/workflows/deploy.yml`):**

The GitHub Actions equivalent uses the bicep-action reusable workflow with OIDC authentication and an environment gate before deploy. The structure is analogous: WhatIf runs on every pull request, deploy runs on push to `main` after reviewer approval.

### ARM / Azure-Deploy (deprecated)

The Azure-Deploy engine (`innofactorazuredeploy.azurecr.io/azuredeploy`) is the legacy IaC runner for Innofactor VDC deployments. It runs on Azure DevOps pipelines only.

New architypes must not use this format unless:
- The target spoke is an existing Azure-Deploy managed environment requiring incremental changes, or
- No Bicep or Terraform equivalent exists in the module library.

If ARM / Azure-Deploy is used, document the justification in a comment in the JSON config or in a per-architype `README.md`.

---

## Repository structure

```
concierge-architypes/
├── network.json                # ARM / Azure-Deploy format
├── network.bicep               # Bicep / AVM format
├── network/
│   ├── main.tf                 # Terraform root module
│   └── main.auto.tfvars        # Terraform variable defaults (tokens substituted by Concierge)
└── README.md
```

Each top-level name is an architype identifier. Bicep and ARM files sit at the root. Terraform modules use a subdirectory matching the architype name — both `main.tf` and `main.auto.tfvars` must be present in that subdirectory.

---

## Adding a new architype

1. Create IaC files following the naming convention: `{name}.json` / `{name}.bicep` / `{name}/main.tf` + `{name}/main.auto.tfvars`.
2. Use `[#_token_#]` placeholders for all environment-specific values — see the token table above for the full list.
3. Validate that the template deploys correctly when tokens are substituted with representative values.
4. Add CI scaffold files for your IaC type and both target platforms once smoke tests pass — see the CI scaffolding section above.
5. Add a row to the architype table in this README.
6. If this is a new default architype, update the `DefaultArchitype` application setting in the `p-concierge` Function App and in `InnofactorOrg/concierge-app`'s Bicep parameters.

---

## Migration to `innofactororg`

This repository will be transferred to `innofactororg/concierge-architypes` once organisational access controls are confirmed. At that point, the `ArchitypesUri` application setting in `infra/main.innofactor.bicepparam` in the concierge-app repository requires a one-line update. GitHub provides a redirect grace period after repository transfer — provisioning runs in flight will not break during the migration.
