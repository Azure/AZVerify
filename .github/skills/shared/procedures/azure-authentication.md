# Azure Authentication Script Contract

Canonical contract for `.github/skills/shared/scripts/Test-AzureAuth.ps1`. Referenced by all skills that interact with Azure.

---

## Script

- **Path**: `.github/skills/shared/scripts/Test-AzureAuth.ps1`
- **Purpose**: Verify that an Azure CLI or Azure PowerShell session is available before any Azure operation runs.

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
  "subscriptionId": "<id>"
}
```

- **stderr**: Diagnostics only

## Exit Codes

- `0` — authenticated; continue
- non-zero — no Azure session; **HARD GATE**

## Failure Handling

If the script exits non-zero, present:

```text
## Azure Authentication Required

You need an active Azure session.

Option A — Azure CLI:
az login

Option B — Azure PowerShell:
Connect-AzAccount

After authenticating, run this skill again.
```

## Script/pwsh Unavailable — MCP Fallback

If `pwsh` or the script cannot be executed (tool unavailable, binary not on PATH, or any invocation error), attempt an **Azure MCP auth probe** before stopping:

1. Call `mcp_azure_subscription_list` (no arguments needed).
2. **If it returns a list of subscriptions** — the user is authenticated. Extract `subscriptionName` and `subscriptionId` from the first returned subscription to substitute for the script's JSON output. Continue execution as if the script exited `0`.
3. **If it returns an authentication or permission error** — the user is not authenticated. Present the authentication instructions above and stop.
4. **If the Azure MCP tool is also unavailable** — report the following prerequisite message and stop:

```text
## Prerequisites Required

This skill requires either:
- PowerShell 7 (pwsh) with Azure CLI (az) on PATH, OR
- The Azure MCP server available and connected

Neither was available. Please install one of the above and try again.
```

> **Note**: The MCP probe path provides the same guarantee as the script — if `mcp_azure_subscription_list` succeeds, an authenticated Azure session exists. Skills that read the subscription name/ID from the script output should use the MCP-returned values instead.
