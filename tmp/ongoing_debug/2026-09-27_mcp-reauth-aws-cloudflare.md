# MCP plugins keep needing re-login (AWS, Cloudflare)

`claude setup-token` (1y) covers only the Claude subscription. Each MCP server does its own auth.

## Cloudflare: done
User-scope servers `cloudflare-{api,bindings,builds,observability}` in `~/.claude.json`, header `Authorization: Bearer ${CLOUDFLARE_MASTER_TOKEN}` (expanded from env). All 4 servers connect.
- Open: the token used is the *master* token (full scope). You can mint a narrower token (Workers/Builds/Observability read + whatever you want the agent to touch) and point the header at it.
- The plugin's own OAuth copies of these servers no longer show up in `claude mcp list`. If they come back asking for a browser login, ignore them or remove the plugin.

## AWS: blocked on you
`plugin:aws-core:aws-mcp` = `uvx mcp-proxy-for-aws` → uses local AWS creds.
- Fixed: `-32602` was first `NoRegionError`. Added `region = us-east-1` to `~/.aws/config`.
- Remaining: creds come from `aws login` (console session as **root**). Its refresh token expires, so you have to re-login periodically.

Options (pick one):
1. Create an IAM user (not root) with access keys, and put them in `~/.aws/credentials` (or agenix + `credential_process`). They don't expire. Trade-off: static keys on disk. Scope the policy down to what the agent should do.
2. Set up IAM Identity Center and use `aws sso login` with a longer session (configurable up to 90d). One login per session window.
3. Keep `aws login`; just run it when it expires.
