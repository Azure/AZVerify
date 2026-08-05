---
name: azv-diagram-to-bicep
description: Generate deployment-ready Bicep templates and PowerShell scripts from an approved Draw.io Azure architecture diagram. Parses the diagram, generates a user-editable .bicepparam file with descriptive comments, validates against Azure constraints, and outputs modular Bicep with deployment scripts.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Generate Bicep templates and PowerShell deployment scripts from a Draw.io Azure architecture diagram.

**Input**: A Draw.io diagram file (`.drawio` or `.drawio.xml`) in the workspace. The user can specify the file path, or the skill will look for `.drawio` files in the workspace.

**Tools required**: File system tools (read/write files), Bicep MCP server (for best-practice validation)

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping (used for reverse-lookup: image path → resource type)
- `.github/skills/shared/azure-resource-configs.md` — Per-resource-type configuration schemas and auto-detection rules
- `.github/skills/shared/data/azure-property-paths.json` — Azure Property Retrieval Mapping (MCP tools, CLI fallbacks, ARM JSON paths, defaults)
- `.github/skills/shared/azure-deployment-verification.md` — **Pre-deployment verification rules (MUST run before presenting results)**

**Shared procedures** (MUST follow):
- `.github/skills/shared/bicep-best-practices.md` — **Bicep generation rules, defaults, and security settings (MUST read before generating Bicep)**
- `.github/skills/shared/version-currency.md` — **Version verification rules (MUST verify before generating code)**
- `.github/skills/shared/procedures/diagram-parsing.md` — Diagram-to-resource-model parsing procedure

---

---

## Steps

### 1. Accept Draw.io Diagram Input

Identify the Draw.io diagram to process.

**If the user specifies a file path:**
- Verify the file exists and is a `.drawio` or `.drawio.xml` file
- Read the file contents

**If no file is specified:**
- Search the workspace for `.drawio` files
- If exactly one is found, use it (announce which file)
- If multiple are found, present the list and ask the user to select one
- If none are found, ask the user to provide a diagram file

### 2. Parse Diagram into Resource Model

Follow the procedure in `.github/skills/shared/procedures/diagram-parsing.md` to parse the Draw.io XML into a structured resource model.

Display the parsed resource model as a table with columns: #, Resource, Type, Container, plus any connections.

### 3. Check for Existing Bicepparam File

Before generating new files, check if infrastructure already exists:

1. Look for a file named `<diagram-name>.bicepparam` in the same directory as the Draw.io file
2. **If found**: Load it, identify any new resources from the diagram not yet represented, and present a summary. Merge new parameters with the user's existing values preserved.
3. **If not found**: Proceed to generate everything fresh (Step 4)

### 4. Generate Bicep Templates and Bicepparam File

Generate and **write each file to disk immediately** as it is produced — do not accumulate file contents in memory or hold them for a combined response. Do not wait for user confirmation — the `.bicepparam` file is the user-editable configuration, and the user can modify it and redeploy at any time.

**Critical — response verbosity rule**: After writing each file, emit only a single confirmation line (e.g., `✓ Written: modules/networking.bicep`). Do **not** echo file contents back into the response. This prevents hitting response length limits on complex diagrams.

Use the schemas defined in `.github/skills/shared/azure-resource-configs.md` for per-resource defaults and the rules in `.github/skills/shared/bicep-best-practices.md` for Bicep structure.

**Output structure:**
```
<solution-folder>/
├── main.bicep                    # Entry point — orchestrates all modules
├── <diagram-name>.bicepparam     # User-editable parameter values with comments
└── modules/
    ├── networking.bicep          # VNets, subnets, NSGs, peerings, private endpoints
    ├── compute.bicep             # VMs, App Services, Container Apps
    └── data.bicep                # SQL, Cosmos DB, Storage, Key Vault
```

**Bicep generation rules:**

1. **main.bicep**:
   - `targetScope = 'resourceGroup'`
   - Declare all parameters with `@description()` decorators explaining each setting
   - Include `@allowed()` where a fixed set of values applies (e.g., environment names)
   - Use default values on parameters where a sensible default exists
   - Mark sensitive parameters with `@secure()` (passwords, keys, connection strings)
   - Module references for each category — omit the `name` field on module blocks
   - Outputs for key resource IDs and endpoints

2. **Module files** (networking.bicep, compute.bicep, data.bicep):
   - Only generate modules that have resources (skip empty categories)
   - Use `parent:` property for child resources (e.g., subnets under VNet) — never `/` in name
   - Add `existing` resource blocks when referencing a parent not declared in the same file
   - Use symbolic references (`foo.id`) instead of `resourceId()`
   - Use secure defaults: `httpsOnly: true`, `minimumTlsVersion: '1.2'`, `publicNetworkAccess: 'Disabled'` where private endpoints exist
   - Use user-defined types instead of open `array`/`object` where appropriate

3. **`<diagram-name>.bicepparam`**:
   - `using 'main.bicep'`
   - Include **all** parameter values
   - Add comments above each parameter or group explaining:
     - What the setting controls in plain language
     - 2-3 common alternatives with a one-line description
     - Cost impact where relevant (e.g., "~$30/mo" vs "~$140/mo")
     - Capacity/scaling consequences (e.g., "A /24 gives 251 usable IPs")
     - Security consequences where applicable
   - Use `readEnvironmentVariable()` for sensitive values (passwords, keys)
   - Keep each comment block to 1-3 lines — concise, not exhaustive

4. **Parameter naming**: Use camelCase, descriptive names (e.g., `vmSize`, `appServicePlanSkuName`, `vnetAddressPrefix`)

**File write order** (write and confirm each before moving to the next):
1. `modules/networking.bicep` (if networking resources exist)
2. `modules/compute.bicep` (if compute resources exist)
3. `modules/data.bicep` (if data resources exist)
4. Any additional module files (e.g., `modules/identity.bicep`, `modules/monitoring.bicep`)
5. `main.bicep`
6. `<diagram-name>.bicepparam`

**Bicepparam comment guidelines:**
```bicep
using 'main.bicep'

// Azure region for all resources. Options: eastus, westeurope, westus2, northeurope
param location = 'eastus'

// VNet address space. /16 gives room for many subnets; /24 limits to ~251 hosts total.
param vnetAddressPrefixes = ['10.0.0.0/16']

// VM size — controls CPU, memory, cost.
//   Standard_B2s    → 2 vCPU, 4 GB  (~$30/mo) — dev/test
//   Standard_D2s_v3 → 2 vCPU, 8 GB  (~$70/mo) — general workloads
//   Standard_D4s_v3 → 4 vCPU, 16 GB (~$140/mo) — heavier workloads
param vmSize = 'Standard_B2s'
```

**Rules for defaults:**
- Use cost-effective defaults (e.g., `Standard_B2s` for VMs, `S1` for App Service Plans, `Standard_LRS` for Storage)
- Default region: `eastus`
- Enable secure defaults: HTTPS only, TLS 1.2 minimum, deny public access where private endpoints exist
- Do NOT default to production-scale settings — prefer dev/test sizing that can be scaled up
- **Version currency** — always verify runtime stacks, API versions, and OS images are current before using them (see "Version Currency" section above). Never blindly copy defaults from reference files without checking they are still current.

### 5. Validate Generated Bicep

After generating all files, run the **full verification ruleset** defined in `.github/skills/shared/azure-deployment-verification.md`. This is mandatory — do not skip or partially run verification.

Read the shared verification reference and check every applicable rule category:
1. **SKU dependency rules** — e.g., WAF_v2 requires a WAF policy, VNet integration requires Standard+ App Service Plan
2. **Resource compatibility rules** — e.g., backend protocol matches, private DNS zones match service type
3. **Networking rules** — e.g., no subnet overlap, dedicated subnets for App Gateway/Firewall/Bastion
4. **Security rules** — e.g., TLS 1.2+, HTTPS enforced, `@secure()` decorators, public access disabled with private endpoints
5. **Regional availability rules** — e.g., resource/SKU availability, capacity constraints, paired region suggestions
6. **Version currency rules** — e.g., runtime stacks current, API versions latest stable, Kubernetes supported

Also verify:
- **Bicep best practices**: Confirm all generated Bicep follows the Bicep MCP best-practice rules
- **Missing dependencies**: Flag resources that need other resources not in the diagram (e.g., a VM without a NIC — add it automatically)

**Present results as a compact summary only** — list each check category with a pass/fail status and a one-line note per issue. Do not reproduce file contents or full rule descriptions in the response. Errors must be auto-fixed by updating the already-written file on disk (re-write the affected file and confirm `✓ Fixed: <filename>`). Do not present generated code that contains known errors.

### 6. Write README and Present Output Summary

Write a `README.md` to the output root directory (alongside `main.bicep`) containing:
- **Source** (diagram file path)
- **Generated date**
- **Pre-deployment verification results** (pass/warning/error counts and details)
- **Generated Files** table (file path + description for every generated file)
- **Deployment commands** (`az deployment group create` and `New-AzResourceGroupDeployment` examples with a placeholder resource group)
- **Next Steps** section: edit `.bicepparam` to set real values, related skills (azv-bicep-whatif, azv-bicep-diagram-sync, azv-bicep-policy-check)

After writing the README, present the same summary in the chat response:

```
## Infrastructure Code Generated

**Source diagram:** webapp-private-endpoint-vm/webapp-private-endpoint-vm.drawio
**Output directory:** webapp-private-endpoint-vm/

### Generated Files
| File | Description |
|------|-------------|
| main.bicep | Entry point — 3 module references, all params with @description |
| <diagram-name>.bicepparam | User-editable parameter values with comments |
| modules/networking.bicep | VNet, 2 subnets, private endpoint |
| modules/compute.bicep | VM, App Service + Plan |

### Customize
Edit `<diagram-name>.bicepparam` to change any deployment settings.
Each parameter has comments explaining the setting, alternatives, and cost.

### Deploy
```powershell
az deployment group create --resource-group "my-rg" --template-file main.bicep --parameters @<diagram-name>.bicepparam
```
```

---

## Important Notes

- This skill operates **independently** — it does not require sketch-to-diagram or diagram-azure-sync.
- The `.bicepparam` file is the persistent, user-editable source of truth for deployment settings. The user can open it in any editor, change values, and redeploy. Each parameter has comments explaining what it does and the consequences of changing it.
- Files are written to disk **one at a time** as they are generated — do not accumulate content in the response. Each file emits only a single `✓ Written:` confirmation line. This keeps responses within length limits for complex diagrams.
- Generated Bicep uses **secure defaults** — HTTPS only, TLS 1.2+, public access disabled where private endpoints are present.
- Bicep modules are only generated for categories that have resources (no empty module files).
- All generated Bicep MUST follow the best practices from the Bicep MCP server (`get_bicep_best_practices`). Call this tool before generating code.
- Reference `.github/skills/shared/azure-stencil-mapping.json` for icon-to-resource-type reverse lookups during diagram parsing.
- Reference `.github/skills/shared/azure-resource-configs.md` for per-resource-type configuration schemas and defaults.
