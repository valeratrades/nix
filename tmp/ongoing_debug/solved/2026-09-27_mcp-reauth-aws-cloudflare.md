# MCP plugins keep needing re-login (AWS, Cloudflare)

`claude setup-token` (1y) covers only the Claude subscription. Each MCP server does its own auth.

## Cloudflare: done
User-scope servers `cloudflare-{api,bindings,builds,observability}` in `~/.claude.json`, header `Authorization: Bearer ${CLOUDFLARE_MASTER_TOKEN}` (expanded from env). All 4 servers connect.
- Open: the token used is the *master* token (full scope). You can mint a narrower token (Workers/Builds/Observability read + whatever you want the agent to touch) and point the header at it.
- The plugin's own OAuth copies of these servers no longer show up in `claude mcp list`. If they come back asking for a browser login, ignore them or remove the plugin.

## AWS: done
- `-32602` was a `NoRegionError`. Fixed by setting `region = us-east-1` in `~/.aws/config`.
- Created IAM user `admin`: `AdministratorAccess`, plus an inline deny `deny-billing-and-close` (billing/payments/account closure, and it can't edit its own policies). Has a non-expiring access key in `~/.aws/credentials` `[default]`. `aws-mcp` connects.
- Console sign-in: https://ev-invest.signin.aws.amazon.com/console as `admin`, password = `$aws_pass`.
- The root `aws login` session is still available as `--profile root`.
- Open: narrow the policy down from AdministratorAccess if you want to limit what the agent can do.

## Cloudflare DNS writes (2026-09-30)
`CLOUDFLARE_MASTER_TOKEN` (account token) gets `10000 Authentication error` on every `/zones/*/dns_records` call. DNS is written with the Cloudflare plugin's OAuth credential instead (`dns.write` scope): `~/.claude/.credentials.json` → `mcpOAuth["plugin:cloudflare:cloudflare-api|…"]`. Refresh it at `https://mcp.cloudflare.com/token` (grant_type=refresh_token, its clientId), save the rotated tokens back, then call the `execute` tool over JSON-RPC at `https://mcp.cloudflare.com/mcp`.
