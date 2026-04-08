# Draw.io Diagram Conventions

Shared construction rules for all AzVerify skills that generate Draw.io diagrams. Skills reference this file instead of carrying duplicated rules.

---

## 1. Canvas Wrapper Format

Always wrap diagrams in the `<mxfile><diagram>` structure. Never emit a bare `<mxGraphModel>`.

```xml
<mxfile>
  <diagram name="Architecture Overview" id="overview">
    <mxGraphModel dx="0" dy="0" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1900" pageHeight="1000" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- resource and edge cells here -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

**Page dimension defaults:**
- Standard: `pageWidth="1900" pageHeight="1000"` (RG container: `x=20 y=20 w=1820 h=930`)
- Compact 3-tier web app (≤15 resources): `pageWidth="1400" pageHeight="780"`

Multi-page files: use one `<diagram>` element per page inside a single `<mxfile>`.

---

## 2. Stencil Mapping Lookup

**MANDATORY**: Check `.github/skills/shared/azure-stencil-mapping.json` for every resource type before constructing any icon path. The mapping lists all known exceptions — wrong categories, non-existent files, and naming surprises. Do NOT skip this step or guess based on the ARM namespace.

For resource types genuinely absent from the mapping, derive the path from the azure2 stencil convention:
```
img/lib/azure2/<category>/<PascalCase_Resource_Name>.svg
```

**Critical known traps:**
- `Microsoft.Web/sites` (App Service) → `img/lib/azure2/compute/App_Services.svg`
- `Microsoft.Web/serverFarms` (App Service Plan) → `img/lib/azure2/app_services/App_Service_Plans.svg` (**not** `compute/`)
- There is no generic `Event_Grid.svg` — use `System_Topic.svg`, `Event_Grid_Topics.svg`, or `Event_Grid_Domains.svg`
- `Microsoft.AppConfiguration/configurationStores` → `img/lib/mscae/App_Configuration.svg` — this icon is in the **mscae** library, **not** azure2. There is no `App_Configuration.svg` or `App_Configurations.svg` in azure2 at all; using any azure2 path produces an empty broken icon.
- When uncertain about any path, verify it exists at `https://github.com/jgraph/drawio/tree/dev/src/main/webapp/img/lib/azure2`
- If no match, use the closest available icon and note the gap

---

## 3. Resource Shape Rules

For each resource icon cell:
- **Style**: `aspect=fixed;html=1;points=[];align=center;image;resizable=0;image=<imagePath>;verticalLabelPosition=bottom;verticalAlign=top;`
- **`verticalLabelPosition=bottom;verticalAlign=top;` is required on every icon cell.** Without it the label renders over the icon, making the shape appear broken or invisible.
- Do NOT include `imageAspect=0;` — it stretches non-square SVGs and distorts icons.
- For icons marked `requiresImageAspect1: true` in `azure-stencil-mapping.json` (currently: **Application Insights**), you MUST add `imageAspect=1;` to the style string. This tells Draw.io to preserve the SVG's native non-square proportions. Omitting it on these icons causes visible distortion.
- **Label**: set to the resource name
- **Size**: use `defaultWidth`/`defaultHeight` from the stencil mapping (typically 48–50px square)

---

## 4. Container Shape Rules

Resource Groups, VNets, and Subnets are containers. All use `container=1;collapsible=0;pointerEvents=0;rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;`

| Container | fillColor | strokeColor | Border |
|-----------|-----------|-------------|--------|
| Resource Group | `#fff2cc` | `#d6b656` | solid |
| VNet | `#dae8fc` | `#6c8ebf` | `dashed=1;dashPattern=5 5` |
| Subnet | `#e1d5e7` | `#9673a6` | `dashed=1;dashPattern=2 2` |

**Icon cell inside each container**: Create a 30×30 image `mxCell` at `x=10, y=10` relative to the container, using the container resource's `imagePath` from the stencil mapping. ID convention: `<container-id>-icon`.

**Container sizing** (size to content — never expand to fill canvas):
- Subnet with 1 icon ≈ 200–250px wide; 2–4 icons ≈ 300–500px wide
- VNet: wrap its subnets with ~20px margins on all sides
- Resource Group: wrap the VNet and any outside resources with ~30px margins
- Oversized empty containers are a diagram quality defect

---

## 5. Edge Rules

**Parent**: Always set `parent="1"` (the root cell) on every edge, regardless of where source/target cells live in the container hierarchy. This prevents Draw.io routing errors for cross-container edges.

**Labels (required)**: Every edge MUST have a short descriptive `value`. Never leave `value=""`. Use the relationship type and direction as a guide (e.g., `"hosts"`, `"reads secrets"`, `"VNet integration"`, `"private link"`, `"backend pool"`, `"VNet peering"`).

All edges: `rounded=1;orthogonalLoop=1;jettySize=auto;html=1;`

**Style by relationship type:**

| Relationship | strokeColor | strokeWidth | Other |
|-------------|-------------|-------------|-------|
| `connects` (data flow) | `#0078D4` | 2 | `endArrow=block;endFill=1` |
| `depends` (dependency) | `#999999` | 1 | `dashed=1;endArrow=open;endFill=0` |
| `secures` (private link / security) | `#E81123` | 2 | `endArrow=block;endFill=1` |
| `peers` (VNet integration / network) | `#00A4EF` | 2 | `dashed=1` |
| `routes` (routing) | `#0078D4` | 2 | `endArrow=block;endFill=1` |

**Managed Identities**: Every Managed Identity (`Microsoft.ManagedIdentity/userAssignedIdentities`) MUST have at least one `depends` edge connecting it to the resource it is assigned to (e.g. the App Service, App Gateway, or VM that uses it). A Managed Identity with no edges is a diagram defect — it conveys no architectural information and appears as an orphaned icon.

## 6. VNet Integration Special Case

An App Service connected to a VNet Integration subnet is **not** a traffic hop.

- **Do NOT** place the App Service inside the integration subnet container
- **Do NOT** draw a directed `connects` edge to the subnet
- **Do**: keep the App Service **outside** the VNet container
- **Do**: draw a dashed `peers` edge from the App Service to the integration subnet, labeled `"VNet integration"`
- **Do**: label the subnet with its delegation (e.g., `"snet-integration (delegated: Microsoft.Web/serverFarms)"`)

This matches how Azure documentation illustrates VNet Integration: the App Service joins the subnet's address space for outbound routing but is not physically placed in the VNet.

---

## 7. Layout Rules

### 7a. Screen-fit target

Diagrams must fit within a **1900×1000 viewport** (full-HD landscape) with no horizontal scrolling on the Architecture Overview page.

### 7b. Choose a layout pattern

**Left-to-right flow** (preferred for standard 3-tier web architectures):
Use when the architecture has a dominant traffic path — internet → ingress → application → data. Apply for App Gateway / Front Door → App Service / Container App → SQL / Cosmos DB, even when a VNet is present.

Column order:
1. Internet-facing resources outside VNet (Public IP, public DNS zone)
2. VNet with stacked subnets (ingress top, integration middle, Private Link bottom)
3. Application tier outside VNet (App Service Plan above, App Service below)
4. Supporting services at right (Key Vault top, App Insights middle)

Canvas: `pageWidth="1400" pageHeight="780"` for ≤15 resources.

**2×2 zone grid** (only when all four zones are meaningfully populated):

**Do NOT apply the zone grid to standard 3-tier web architectures** — zone grids create long cross-zone edges in linear architectures (e.g., App Service in "Application" zone → Private Endpoint in "Ingress" zone), breaking semantic proximity and producing diagonal lines that make the diagram unreadable.

| Position | Zone | Typical contents |
|----------|------|------------------|
| Top-left | Ingress | Public IP, App Gateway, WAF policy, DNS zone, Front Door |
| Top-right | Application | App Services, ASPs, Container Apps, Function Apps |
| Bottom-left | Data | SQL, Key Vault, Storage accounts, App Config, Cosmos DB |
| Bottom-right | Operations | Bastion hosts, jump-box VMs, management VMs |

Reference geometry (adjust proportions to resource counts):
- RG container: `x=20 y=20 w=1820 h=930`
- Row 1 zones (y=80, h=380): Ingress `x=30 w=430` | Application `x=480 w=1310`
- Row 2 zones (y=480, h=420): Data `x=30 w=960` | Operations `x=1010 w=780`

**Flat environment** (no networking tier): skip zone containers entirely. Arrange resources directly inside the RG — ingress/security left, application middle, data right.

### 7c. Hub-and-spoke (when a resource has ≥5 connections)

Placing all connected resources in a flat row causes edges to overlap and cross. Place the hub at centre and distribute peers in distinct spatial directions:

| Direction | Typical candidate |
|-----------|-------------------|
| ↑ Up | Resource the hub *depends on* (e.g. App Service Plan) |
| ← Left | Security resources (Key Vault, identity) |
| → Right | Data / storage resources (Storage Account, database) |
| ↓ Down | Identity resources (Managed Identity, RBAC targets) |
| ↙ Down-left | Outbound integrations (Communication Services, Event Hub) |
| → Far right | Cross-RG external dependencies |

No two peer resources should share the same compass direction from the hub. Chains that hang off a peer (e.g. Email Service → domain children) can continue in the same direction as the peer.

### 7d. Semantic proximity rules

Every edge should connect to its nearest spatial neighbour — violating these creates long diagonal lines that make diagrams unreadable:

- **Public DNS Zone** → ingress column (leftmost), next to the Public IP it records. Never place it in a Data zone or far right.
- **Key Vault** → adjacent to its primary consumer. When consumed by both App Gateway (SSL) and App Service (secrets), place it to the right of the App Service and waypoint the App Gateway → Key Vault edge through the column gap.
- **Private DNS Zones** → inside or directly adjacent to the Private Link subnet they serve.
- **App Service Plan** → immediately above the App Service it hosts, same x-coordinate. The "hosts" edge should be a short vertical line.
- **SQL resources** (server + database) → directly below or beside the Private Link subnet containing their Private Endpoint, so the PE → SQL edge is a short downward connection.

### 7e. Network Topology Page Layout

When generating a dedicated Network Topology page (multi-page diagrams), follow these rules to keep the diagram readable without horizontal scrolling:

**Grid layout (3 columns × N rows):** Arrange subnets in a compact grid grouped by function, not a flat horizontal row. Target ≤3 columns regardless of subnet count.

| Row | Typical subnets | Rationale |
|-----|----------------|----------|
| Row 1 | External / ingress subnets (API Ext, Dashboard Ext, AppGateway) | Entry points together |
| Row 2 | Internal / integration subnets (API Int, Dashboard Int, VMs) | Backend tier together |
| Row 3 | Data subnets (SQL, KeyVault, Storage) | Data tier together |
| Row 4 | Support subnets (AppInsights, AppConfig, BuildAgents) | Supporting services |

**Pair related subnets vertically.** Place External above Internal for the same service (e.g., API External at row 1 col 1, API Internal at row 2 col 1). This makes the private endpoint → VNet integration pattern visually obvious.

**Subnet sizing:** Size subnets to their content. A subnet with 1–3 icons needs ~450×230px, not 560×380px. Oversized empty subnets are a readability defect. Place NSG and route table icons at the bottom-right of each subnet in a compact row (36px icons), not far below the resources.

**Place supporting resources inside their parent subnet.** App Service Plans, Managed Identities, and WAF Policies MUST be placed inside the subnet of the resource they serve (e.g., `asp-api` inside the API Internal subnet next to `app-api`). Use 36px icons for these supporting resources vs 50px for primary resources to establish visual hierarchy. Placing them in a scattered row at the bottom of the VNet creates long diagonal edges that cross the entire diagram — this is the single most common readability defect in network diagrams.

**Route table visualization:** Do NOT place a single route table icon at VNet level with radiating edges to every subnet. Instead, add a small route table icon (36px, fontSize=9) inside each subnet showing which route table applies. This eliminates visual clutter from N edges while making the assignment clear per-subnet. If a subnet has a unique route table (e.g., AppGateway), show that specific route table inside it.

**Legend placement:** Place the legend as a horizontal bar below the VNet container (inside the RG), not as a tall side panel. Target ~full-width × 170px. Remove verbose ASG listings if ASG names are already shown inline in resource labels as `[asg-name]`. Keep only: edge type legend (4 line types), a one-liner about ASG label conventions, and a route table note.

**Page dimensions:** Target `pageWidth="1800" pageHeight="1600"` for 12 subnets. The diagram MUST fit within a 1920px-wide display without horizontal scrolling. Never exceed `pageWidth="1900"` for network pages — the old guidance to "exceed 1900px" produced unreadable diagrams that required scrolling.

### 7f. Anti-patterns to avoid

1. Triggering the 2×2 zone grid for standard 3-tier web apps — causes cross-zone backward edges and long diagonals. Use left-to-right flow instead.
2. Placing the public DNS Zone on the far right — it belongs next to the Public IP.
3. Routing the App Gateway → Key Vault edge as a bottom-of-canvas diagonal — place Key Vault near App Service and waypoint through the column gap.
4. Over-sizing VNet containers to fill a zone quadrant — always size to content.
5. Placing ASPs, Managed Identities, or WAF Policies in a row at the bottom of the VNet, far from the resources they serve — absorb them into the parent subnet instead.
6. Using a single central route table icon with radiating edges to every subnet — add a per-subnet route table icon instead.
7. Building the network page as a wide flat layout (2 rows × 6+ columns) — use a 3-column grid grouped by function tier.
8. Placing a tall legend panel on the right side of the diagram, pushing the total width beyond the viewport.

---

## 8. Pre-delivery Completeness Verification

Before presenting to the user, cross-check the generated XML against the resource model:

1. For every resource in the resource model, verify its `id` appears as an `mxCell` in the XML.
2. For every container (Resource Group, VNet, Subnet), verify both the container `mxCell` and its icon `mxCell` (`<id>-icon`) exist.
3. For every relationship, verify a corresponding edge `mxCell` exists with the correct `source` and `target`.
4. Verify all edges have `parent="1"`.

**If any resource is missing from the XML, do NOT proceed** — fix the XML before presenting to the user.

Present the verification as a checklist:
```
## Pre-delivery Verification
- [x] vm-01 (Virtual Machine) → mxCell found
- [x] vnet-01 (VNet container + icon) → mxCells found
- [x] subnet-01 (Subnet container + icon) → mxCells found
- [x] edge-vm-nic → mxCell found, parent="1" ✓

All resources verified. Proceeding to save.
```
