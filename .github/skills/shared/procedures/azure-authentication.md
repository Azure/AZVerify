# Azure Authentication Script Contract

Canonical contract for `.github/skills/shared/scripts/Test-AzureAuth.ps1`. Referenced by skills that interact with Azure. Backend requirements are workflow-specific: legacy discovery can accept either backend; expected-aware Bicep drift discovery requires Azure CLI.

---

## Script

- **Path**: `.github/skills/shared/scripts/Test-AzureAuth.ps1`
- **Purpose**: Verify that an Azure CLI or Azure PowerShell session is available before Azure operations that support either backend.

## Invocation

```powershell
pwsh .github/skills/shared/scripts/Test-AzureAuth.ps1
```

## Output

- **stdout**: Single JSON object

```json
{
  "authenticated": true,
  "subscriptionName": "<name>",
  "subscriptionId": "<id>",
  "tenantId": "<tenant-id>",
  "account": "<user-or-spn>",
  "method": "AzPowerShell|AzureCLI"
}
```

> The `method` field is either `AzPowerShell` (Az PowerShell module) or `AzureCLI` (Azure CLI). The script probes Az PowerShell first and falls back to Azure CLI. The caller must enforce the selected workflow's backend requirement; the returned authenticated status alone does not guarantee that the required backend was used.

- **stderr**: Diagnostics only

## Exit Codes

- `0` — authenticated; continue when the workflow's backend requirement is met
- non-zero — no Azure session.

## Failure Handling

If the script exits non-zero, present:

```text
## Azure Authentication Required

You need an active Azure session. Use the backend required by the selected workflow:

Option A — Azure CLI:
az login

Option B — Azure PowerShell (legacy/manual workflows only; not expected-aware Bicep drift discovery):
Connect-AzAccount

After authenticating, run this skill again.
```

For expected-aware Bicep drift discovery (`-ExpectedModel`), require Azure CLI specifically for scope lookup, inventory, and token acquisition. An Az PowerShell-only session does not satisfy this requirement, even if the generic probe succeeds via Az PowerShell. Use `az login` and the explicitly selected subscription. Do not silently switch expected-aware discovery to Az PowerShell or fall back to deployment `what-if`.

The legacy/manual discovery path may use Azure CLI or an authenticated Az PowerShell session as supported by its script contract.

## Script/pwsh Unavailable — MCP Fallback (Legacy Workflows Only)

For legacy workflows that permit Azure MCP, if `pwsh`/`powershell.exe` or the script cannot be executed (tool unavailable, binary not on PATH, or any invocation error), attempt an **Azure MCP auth probe** before stopping:

1. Call `mcp_azure_subscription_list` (no arguments needed).
2. **If it returns a list of subscriptions** — the user is authenticated. Extract `subscriptionName` and `subscriptionId` from the first returned subscription to substitute for the script's JSON output. Continue execution as if the script exited `0`.
3. **If it returns an authentication or permission error** — the user is not authenticated. Present the authentication instructions above and stop.
4. **If the Azure MCP tool is also unavailable** — report the following prerequisite message and stop:

```text
## Prerequisites Required

This skill requires either:
- PowerShell 5.1 (powershell.exe) or higher (`pwsh`) with Azure CLI (az) on PATH, OR
- The Azure MCP server available and connected

Neither was available. Please install one of the above and try again.
```

> **Note**: The MCP probe path provides the same guarantee as the script — if `mcp_azure_subscription_list` succeeds, an authenticated Azure session exists. Skills that read the subscription name/ID from the script output should use the MCP-returned values instead.

This MCP fallback does **not** satisfy the Azure CLI-only prerequisite for expected-aware Bicep drift discovery. If Azure CLI authentication cannot be established for that path, stop; do not treat an MCP or Az PowerShell session as equivalent.
