# AzVerify1 Functional-Test Artifacts

**Source:** Live `AzVerify1` resource group and `azverify1/azverify1.drawio`
**Generated:** 2026-10-31

## Pre-deployment verification

| Check | Result | Notes |
|---|---|---|
| Bicep build | PASS | `main.bicep` and `modules/data.bicep` compile. |
| Parameter build | PASS | `azverify1.bicepparam` compiles. |
| ARM deployment validation | PASS | Validated against `AzVerify1`; no resources were changed by validation. |
| Bicep drift check | PASS | Complete result: one resource in sync, no create, modify, or delete candidates. |
| Diagram parse | PASS | The diagram parser found the resource-group container and storage account. |
| Draw.io MCP validation | NOT RUN | The MCP was unavailable; the skill's direct-file fallback was used. |

## Generated files

| File | Description |
|---|---|
| `azverify1.drawio` | Diagram of the live storage account in its resource group. |
| `original-request.md` | Scope, discovery summary, and relationship record. |
| `main.bicep` | Resource-group entry point and module parameters. |
| `azverify1.bicepparam` | Editable parameter values and security notes. |
| `modules/data.bicep` | Storage account resource declaration. |

## Deploy

Review the parameters and target before deploying:

```bash
az deployment group create \
  --resource-group "<resource-group>" \
  --template-file main.bicep \
  --parameters @azverify1.bicepparam
```

The test storage account already exists in `AzVerify1`. The deployment command above is an example only and was not run.

## Next steps

- Review the diagram and generated parameters before reusing them.
- Use `azv-bicep-drift-detection` to compare Bicep with Azure, and `azv-bicep-policy-check` to evaluate policy restrictions.
