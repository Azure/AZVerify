---
name: azv-sketch-to-diagram
description: Convert a rough sketch or drawing of an Azure architecture into a professional Draw.io diagram using Azure-specific shapes. Upload a sketch image or describe your architecture, and this skill will identify resources, ask clarifying questions, validate feasibility, and generate the diagram via the Draw.io MCP.
license: MIT
metadata:
  author: AzVerify
  version: "1.0"
  project: AzVerify
---

Convert a rough Azure architecture sketch into a professional Draw.io diagram.

**Input**: A sketch image (PNG, JPG, photo of whiteboard) uploaded through chat, or a text description of an Azure architecture.

**Tools required**: Draw.io MCP (`mcp_drawio_create_diagram` or `mcp_draw_io_create_diagram`)

**Reference files**:
- `.github/skills/shared/azure-resource-model.md` — Shared resource metadata model definition
- `.github/skills/shared/azure-stencil-mapping.json` — Azure resource type to Draw.io stencil mapping (includes non-obvious icon paths and naming exceptions)

---

## Steps

### 1. Accept and Analyze the Sketch

Examine the user-provided input (image or text description) and identify all Azure resources, connections, and groupings.

**If the user provided an image:**
- Analyze the image to identify shapes, labels, icons, text, arrows, lines, and containment boundaries
- Map each identified element to an Azure resource type using the resource types listed in `.github/skills/shared/azure-resource-model.md`
- Identify connections between resources (lines, arrows) and their direction
- Identify containment (resources drawn inside boundaries labeled as VNets, subnets, resource groups)
- If the image is blurry or low-resolution, do your best and flag uncertain elements for clarification

**If the user provided a text description:**
- Parse the description to identify Azure resource types, quantities, and relationships
- Infer connections and containment from the description context

### 2. Build the Resource Model

Construct a resource model (as defined in `.github/skills/shared/azure-resource-model.md`) from the analysis:

```json
{
  "resources": [
    {
      "id": "<slug>",
      "type": "<Microsoft.Provider/resourceType>",
      "name": "<resource-name>",
      "resourceGroup": "<rg-name>",
      "location": "",
      "properties": {},
      "relationships": [
        { "targetId": "<other-id>", "type": "contains|connects|depends|peers|secures|routes" }
      ]
    }
  ]
}
```

Use the resource types from the mapping in `.github/skills/shared/azure-stencil-mapping.json` to ensure each resource can be represented with a proper Azure icon.

**You MUST output the full resource model JSON in the chat** so the user can review it before diagram generation. This serves as a checkpoint — every resource listed here must appear in the final diagram.

### 3. Ask Clarifying Questions

Before proceeding, check for ambiguities and ask the user **only essential** questions. Limit to the minimum needed to produce a correct diagram.

**Ask clarifying questions when:**
- An element could be two or more different Azure resource types (e.g., "is this a VM or a Container Instance?")
- A connection type is ambiguous (e.g., "is this VNet peering or a VPN connection?")
- Resources are drawn but not labeled and cannot be confidently identified
- The sketch lacks enough information to produce a meaningful diagram (ask for a text description)
- A containment boundary is unclear (e.g., "is this box a resource group, a VNet, or a subnet?")

**Do NOT ask about:**
- SKUs, pricing tiers, or scaling settings (those belong to the configuration manifest in diagram-to-bicep)
- Deployment regions (unless needed to validate feasibility)
- Resource naming conventions (use sensible defaults from sketch labels)

**Format questions as a numbered list** so the user can answer efficiently:
```
I identified the following from your sketch. A few things need clarification:

1. The element labeled "Web" — is this an **App Service**, **Container App**, or **VM**?
2. The connection between the database and storage — is this a **data flow** or a **Private Endpoint** connection?
3. The outer boundary — is this a **Resource Group** or a **VNet**?
```

Wait for the user's answers and update the resource model accordingly.

### 4. Validate Architecture Feasibility

After the resource model is finalized (with clarifications resolved), validate that the architecture is feasible in Azure:

**Check for:**
- **Invalid resource types**: Any resource type that doesn't exist in Azure. Suggest the closest valid type.
- **Incompatible connections**: Connections Azure doesn't support (e.g., a resource placed in a subnet that can't be subnet-delegated, peering between incompatible VNet configurations).
- **Invalid containment**: Resources placed inside containers they can't belong to (e.g., a Storage Account inside a subnet without Private Endpoint, an App Service directly inside a VNet without VNet Integration).
- **Missing implicit dependencies**: Resources that require other resources not in the diagram (e.g., a VM without a NIC, an App Service without an App Service Plan). These should be added automatically or flagged.

**If issues are found**, present a validation summary:
```
## Architecture Validation

I found the following issues with the architecture:

1. ⚠️ **App Service in subnet**: App Services cannot be placed directly in a subnet. 
   → Suggested fix: Add VNet Integration to connect the App Service to the subnet.

2. ❌ **Unknown resource type "DataLake"**: This is not a standard Azure resource type.
   → Did you mean **Azure Data Lake Storage Gen2** (Storage Account with hierarchical namespace)?

3. ℹ️ **VM without NIC**: The VM "web-vm" needs a Network Interface. 
   → I'll add a NIC automatically.

Please confirm the fixes or provide alternatives.
```

Wait for user confirmation before proceeding. If no issues are found, proceed directly to documentation verification.

#### Verify Against Microsoft Documentation (MANDATORY)

> **HARD GATE**: This step is **mandatory** and **must not be skipped**. You MUST call `fetch_webpage` at least once against Microsoft Learn documentation before proceeding to Step 5. Do NOT proceed to diagram generation without completing this verification. Asserting checks pass without actually fetching documentation is not acceptable.

After structural validation, verify the architecture against official Microsoft documentation to ensure the design follows Azure-recommended patterns and uses current, supported Azure services:

**Step 4a — Fetch documentation for EVERY Azure service in the resource model:**

For each distinct Azure service type in the resource model, call `fetch_webpage` against its Microsoft Learn overview page. Construct the URL as `https://learn.microsoft.com/en-us/azure/<service-name>/overview` or the service's main documentation page. This is not optional — you must make at least one `fetch_webpage` call per service type. Examples:
- Storage Account → `https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-static-website`
- Azure Front Door → `https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview`
- Application Gateway → `https://learn.microsoft.com/en-us/azure/application-gateway/overview`

**Step 4b — Check for service retirement or deprecation:**

In the fetched documentation, look for:
- **Retirement notices** (banners, "Important" callouts mentioning retirement dates)
- **Migration recommendations** (e.g., "migrate to Azure Front Door", "use the replacement service")
- **"Classic" or "legacy" labels** that indicate the service has a newer replacement

If a service is retired or on a retirement path, **replace it in the resource model** with the recommended successor and inform the user.

**Step 4c — Verify architecture patterns:**

1. **Verify resource placement constraints** — confirm that resources requiring dedicated subnets (Application Gateway, VNet Integration, Private Endpoints) are modeled correctly according to their official documentation.

2. **Verify connectivity patterns** — confirm that connection types match documented Azure capabilities (e.g., Private Link targets, VNet peering requirements, service endpoint compatibility).

3. **Verify DNS and name resolution** — for architectures using Private Endpoints, confirm the correct Private DNS Zone names (e.g., `privatelink.database.windows.net` for SQL Database) match the documented values.

**Step 4d — Present the verification table:**

The table MUST include the actual URL fetched for each check. A check without a URL means it wasn't actually verified.

```
## Microsoft Documentation Verification

| Check | Status | URL Fetched | Finding |
|-------|--------|-------------|---------|
| Storage Account static website support | PASS | https://learn.microsoft.com/en-us/azure/storage/blobs/storage-blob-static-website | Supported, content served from $web container |
| Azure CDN retirement status | FAIL | https://learn.microsoft.com/en-us/azure/cdn/cdn-overview | Edgio retired Jan 2025, Microsoft classic retiring Sep 2027. Migrate to Front Door. |
| Azure Front Door as CDN replacement | PASS | https://learn.microsoft.com/en-us/azure/frontdoor/front-door-overview | Front Door Standard/Premium is the recommended replacement |
```

**If any check has status FAIL**, update the resource model before proceeding to Step 5 and inform the user of the changes.

### 5. Create Solution Folder

Before generating the diagram, create a dedicated solution folder in the workspace root to hold all artifacts for this architecture:

1. **Derive a folder name** from the architecture description or sketch labels (e.g., `web-app-architecture`, `hub-spoke-network`). Use lowercase kebab-case.
2. **Create the folder** in the workspace root (e.g., `web-app-architecture/`).
3. **Save the original request** into the folder so the input is always stored alongside the results:
   - **If the user uploaded an image**: Save it as `original-sketch.<ext>` (preserving the original format — PNG, JPG, etc.).
   - **If the user provided a text description**: Save the description as `original-request.md` with the user's original text quoted verbatim. Use a simple format:
     ```markdown
     # Original Architecture Request

     > <user's description, preserved exactly as provided>
     ```
   - **If both** an image and a text description were provided, save both files.

This folder will also be used by later skills (diagram-to-bicep, diagram-azure-sync) to store Bicep templates, configuration manifests, and other generated artifacts alongside the diagram.

### 6. Generate the Draw.io Diagram

Using the validated resource model, generate a Draw.io diagram. **Save the diagram inside the solution folder** created in Step 5.

Follow all diagram construction rules in `.github/skills/shared/drawio-diagram-conventions.md` (canvas format, stencil mapping, resource shapes, container shapes, edges, VNet Integration, layout, sizing).

**Sketch-specific layout note**: When the input is a sketch image, treat the sketch's spatial arrangement as the primary layout guide. Preserve the left/right/top/bottom positioning of resources and containers as drawn. The goal is a polished version of the original sketch, not a generic auto-layout. Apply the shared layout rules within those spatial constraints.

Call the Draw.io MCP tool:

```
Use tool: mcp_drawio_create_diagram (or mcp_draw_io_create_diagram)
Parameters:
  - xml: <the generated mxGraphModel XML>
  - fileName: <solution-folder>/<name>.drawio (e.g., "web-app-architecture/web-app-architecture.drawio")
```

### 7. Verify Completeness

Follow the pre-delivery completeness verification procedure in `.github/skills/shared/drawio-diagram-conventions.md` (section 8). Fix any missing resources or edges before proceeding.

### 8. Present for User Review

After generating the diagram, present a summary to the user:

```
## Diagram Generated ✓

I've created the Draw.io diagram with the following resources:

| Resource | Type | Location |
|----------|------|----------|
| web-vm | Virtual Machine | rg-main |
| webstorage | Storage Account | rg-main |
| ... | ... | ... |

**Connections:**
- web-vm → webstorage (data flow)
- ...

The diagram has been saved as `web-app-architecture/web-app-architecture.drawio`.

Would you like to make any changes? For example:
- "Add a load balancer in front of the VMs"
- "Remove the SQL database"
- "Move the storage account to a different resource group"
```

### 9. Handle Change Requests (Review Loop)

If the user requests changes:

1. Parse the change request to understand what to add, remove, or modify
2. Update the resource model accordingly
3. Re-validate the architecture (Step 4) if structural changes were made
4. Regenerate the diagram XML with the changes
5. Call the Draw.io MCP tool again with the updated XML
6. Present the updated summary and ask for further changes

Repeat until the user confirms the diagram is correct.

When the user confirms:
```
Diagram finalized and saved in the `<solution-folder>/` folder.

You can use this folder with the **azv-diagram-to-bicep** skill to generate Bicep templates, 
or with **azv-diagram-azure-sync** to compare it against a live Azure environment.
```

---

## Important Notes

- This skill operates **independently** — it does not require diagram-to-bicep or diagram-azure-sync.
- Do NOT ask about deployment settings (SKUs, tiers, scaling). Those are handled by the configuration manifest in diagram-to-bicep.
- Always use the Draw.io MCP for diagram creation — never output raw XML for the user to manually save.
- Follow all diagram construction rules in `.github/skills/shared/drawio-diagram-conventions.md` — stencil lookup, icon paths, layout patterns, and anti-patterns are all documented there.
- Keep clarifying questions to the minimum needed. Prefer making reasonable assumptions (and stating them) over asking many questions.

