# Draw.io MCP response and edge normalization

The original response body is retained in `mcp-original-response.json`; the XML returned by the MCP is separately preserved, unmodified, in `mcp-returned-unmodified.drawio`. `mcp-generated.drawio` is the normalized MCP output. `raw-fallback.drawio` is the independently written fallback.

The MCP placed the storage-to-identity edge under the Resource Group on the Architecture Overview page and under the outside-VNet services lane on the Network Topology page. The final outputs follow the repository convention and set every edge's parent to the root layer, `1`.

Connector geometry was preserved during normalization:

- The reparented identity edges had no explicit route-point array or source/target point coordinates. Their source/target cell IDs and relative edge geometry were left unchanged, so there were no absolute points requiring translation.
- The VNet peering edges contained two absolute route waypoints and already had parent `1`; both waypoint coordinates were retained unchanged.
- The normalizer translates any explicit route or terminal points by the accumulated parent/container offsets before changing a nested parent to `1`.

The MCP diagnostic reports duplicate IDs `0` and `1` across the two pages. These are the standard root and layer IDs in separate page-local graph models; all other cell IDs are unique within each page. Both MCP and fallback files parse and render both pages.

The first MCP attempt, including the original parent mismatch, is retained as `mcp-original-response-attempt1.json` and `mcp-returned-attempt1.drawio`.
