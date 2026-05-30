# Connection Guide

Step-by-step recipes for connecting external services to your only-agent workspace. Each section is self-contained - skip what you don't use.

**Budget**: 30-60 minutes if you connect everything. 5-15 minutes for a typical 2-3 service setup.

**How to use this guide**: Open Claude in the workspace and say "walk me through `notes/connections.md` - I want to connect [list your tools]." Claude will go section by section, run smoke tests, and debug failures before moving on.

---

## How MCPs work in Claude Code

MCP servers can live in any of these places (Claude Code merges them):
- **User-level**: `~/.claude/settings.json` `mcpServers` (every project)
- **Project-level (recommended for project-scoped)**: `<project>/.mcp.json` (auto-discovered when running Claude in that dir)
- **Project-level (alternate)**: `<project>/.claude/settings.json` `mcpServers`

Use user-level for accounts you reuse across projects (Slack, Notion, Gmail). Use project-level for things scoped to one workspace (e.g., a dedicated Datadog org). When in doubt, use `~/.claude/settings.json` - it's the simplest path.

After editing settings, **restart Claude Code** (`/exit`, then `claude`) for it to take effect.

The shape:

```json
{
  "mcpServers": {
    "<name>": {
      "type": "stdio",
      "command": "<binary>",
      "args": ["..."],
      "env": { "KEY": "value" }
    },
    "<another>": {
      "type": "http",
      "url": "https://..."
    }
  }
}
```

`stdio` servers run a local process. `http` servers are hosted by the vendor. OAuth flows pop a browser on first use.

---

## Pick your stack

Most users want some subset of:

| Service | Type | Skip if... |
|---------|------|------------|
| **GitHub CLI** | `gh` (no MCP) | You don't use GitHub |
| **Slack** | MCP (browser tokens) | You don't use Slack at work |
| **Atlassian (Jira/Confluence)** | MCP (hosted) | You don't track work in Jira |
| **Notion** | MCP (hosted) | You don't write in Notion |
| **Google Workspace (Drive/Sheets/Docs)** | MCP | You don't use Google docs |
| **Gmail** | MCP | You don't want AI in your inbox |
| **Google Calendar** | MCP | You manage time elsewhere |
| **Datadog** | MCP | You don't run production |
| **PagerDuty** | MCP (community) | You don't carry pages |
| **Linear** | MCP (hosted) | You track work elsewhere |
| **Stripe** | MCP (vendor toolkit) | You don't bill via Stripe |

The rule: **connect what you actually touch every week.** Underused MCPs add settings noise and OAuth maintenance for no return.

---

## 1. GitHub CLI

**What it gives you**: PRs, issues, code search, repo metadata. Faster and more complete than any GitHub MCP.

```bash
brew install gh         # or your platform's package manager
gh auth login           # SSH preferred over HTTPS
gh auth status
```

**Smoke test**: `gh pr list --limit 3`

No MCP, no settings.json change. Claude invokes `gh` via Bash.

---

## 2. Slack

**What it gives you**: Read/search messages, send messages, list channels.

**Package**: [`slack-mcp-server`](https://www.npmjs.com/package/slack-mcp-server) (npm, runs via npx)

**Auth**: xoxc/xoxd tokens extracted from your browser. These are YOUR session tokens - they expire when you log out or periodically.

### Setup

1. Open Slack in your **browser** (not the desktop app): `https://<your-workspace>.slack.com`
2. Open DevTools (F12 or Cmd+Option+I)
3. Go to **Application** tab > **Cookies** > `https://app.slack.com`
4. Find the cookie named `d` - copy its value. This is your `xoxd` token. Starts with `xoxd-`.
5. Go to **Console** tab, type: `JSON.parse(localStorage.getItem("localConfig_v2"))["teams"]` and press Enter
6. In the output, find your workspace. The `token` field is your `xoxc` token. Starts with `xoxc-`.

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "slack": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "slack-mcp-server@latest", "--transport", "stdio"],
      "env": {
        "SLACK_MCP_XOXC_TOKEN": "<your-xoxc-token>",
        "SLACK_MCP_XOXD_TOKEN": "<your-xoxd-token>"
      }
    }
  }
}
```

Restart Claude. **Smoke test**: ask Claude to list a few channels.

### Gotchas
- **Tokens expire**. When Slack MCP stops working, re-extract from browser. This WILL happen. Plan for it.
- **`conversations.list` is rate-limited aggressively**. Use `channels_list` for channel ID lookups.
- **`conversations.info` fails on xoxc tokens**. Use `conversations.history` to check a channel.
- **`users.info` needs form-encoded data**, not JSON. The MCP handles this; if you build custom tools, remember it.
- **Channel ID prefixes**: `D` = DM, `G` = group DM, `C` = public channel.
- **Corporate proxy (Zscaler, etc.)**: If Python scripts hit SSL errors, install `truststore`.

### Multi-workspace
Run a second MCP entry with a different name (e.g. `slack-personal`) and a separate token pair.

---

## 3. Atlassian (Jira + Confluence)

**What it gives you**: Read/create/edit Jira issues, search with JQL, read Confluence pages.

**Package**: [Atlassian's hosted MCP](https://www.atlassian.com/platform/remote-mcp-server) - no local install.

```json
{
  "mcpServers": {
    "atlassian": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v1/mcp"
    }
  }
}
```

On first use, Atlassian OAuth opens a browser. Authorize.

**Smoke test**: ask Claude "find my open Jira issues."

### Gotchas
- **JQL examples**: `assignee = currentUser() AND status != Done`, `project = ENG ORDER BY updated DESC`
- **Account ID**: Some operations need your Atlassian account ID. Use `lookupJiraAccountId` with your email.
- **Confluence vs Jira**: One MCP, both products. Most teams pick one as their docs home.

---

## 3b. Linear

**What it gives you**: Read/write Linear issues, projects, cycles, comments.

**Package**: [Linear's hosted MCP](https://linear.app/changelog/2025-mcp).

```json
{
  "mcpServers": {
    "linear": {
      "type": "http",
      "url": "https://mcp.linear.app/sse"
    }
  }
}
```

On first use, browser opens for Linear OAuth.

**Smoke test**: "list my open Linear issues."

### Gotchas
- **Workspace scoping**: OAuth picks one Linear workspace. If you switch workspaces, re-auth.
- **Cycle context**: Cycles are Linear's sprints. The MCP exposes cycle IDs - useful for "what's in the current cycle for team X."
- **Trello / GitHub Projects / Shortcut**: similar shape, separate community MCPs. Pick the one matching your tracker.

---

## 4. Notion

**What it gives you**: Search, read, create, update Notion pages and databases.

**Package**: [Notion's hosted MCP](https://developers.notion.com/docs/get-started-with-mcp).

```json
{
  "mcpServers": {
    "notion": {
      "type": "http",
      "url": "https://mcp.notion.com/mcp"
    }
  }
}
```

On first use, browser opens for Notion OAuth. Authorize against your workspace.

**Smoke test**: "search Notion for my recent pages."

### Gotchas
- **Multi-workspace**: Add a second entry named `notion-personal` (or similar) with the same URL. The second OAuth flow lets you pick a different workspace.
- **Page IDs**: Notion URLs end in the page ID. Use `notion-search` to find pages by title.
- **Standalone pages**: When creating, omit `parent` - the page becomes a top-level draft you can move manually.

---

## 5. Google Workspace (Drive + Sheets + Docs)

**What it gives you**: Search/list/read Drive files, read/write Sheets, read/write Docs.

**Package**: There are several public MCPs. A widely-used one is [`google-workspace-mcp`](https://github.com/taylorwilsdon/google-workspace-mcp). Pick the one whose scope matches your needs.

### Setup (general shape)

1. Create OAuth credentials in [Google Cloud Console](https://console.cloud.google.com):
   - Create or pick a project.
   - APIs & Services > Credentials > Create Credentials > OAuth Client ID > Desktop app.
   - Download the JSON.
2. Install your chosen MCP package per its README.
3. Configure `~/.claude/settings.json` with the OAuth client ID/secret per the package docs.
4. First use opens a browser for Google OAuth consent. Token saves locally.

**Smoke test**: "list my recent Google Docs."

### Gotchas
- **Scopes**: Most packages cover Drive, Sheets, Docs, Slides, Gmail under one OAuth token.
- **Token refresh**: Tokens auto-refresh. If broken, delete the cached token file and re-authorize.
- **Docs formatting**: MCPs handle Docs reading well, but heavy formatting (tables, paragraph styles, images) is tricky. For doc-heavy workflows, build a small Python tool against Google Docs API directly.
- **Personal vs work account**: Run a second MCP entry with a `-personal` suffix and a different token cache path.

---

## 6. Gmail

**What it gives you**: Read, send, search, label emails.

Often bundled with the Google Workspace MCP above (same OAuth scope set). If you want a dedicated package, search [Gmail MCP servers](https://github.com/modelcontextprotocol).

### Gotchas
- **Draft-first, never auto-send.** Tell the agent to draft and show before sending. This is a permanent rule worth adding to `learnings.md`.
- **Multi-account**: Same pattern - separate MCP entry with separate OAuth token.

---

## 7. Google Calendar

**What it gives you**: List, create, update, delete events. Check free/busy.

**Package**: [`@cocal/google-calendar-mcp`](https://www.npmjs.com/package/@cocal/google-calendar-mcp) (npm).

```bash
mkdir -p ~/.gmail-mcp
# Save your OAuth keys as ~/.gmail-mcp/gcp-oauth.keys.json
npx -y @cocal/google-calendar-mcp auth
```

```json
{
  "mcpServers": {
    "google-calendar": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@cocal/google-calendar-mcp"]
    }
  }
}
```

**Smoke test**: "what's on my calendar tomorrow?"

---

## 8. Datadog

**What it gives you**: Query metrics, search logs, monitors, dashboards, traces, incidents.

**Package**: [Datadog MCP CLI](https://docs.datadoghq.com/bits_ai/mcp_server/setup/) (vendor-provided).

Install per the Datadog docs (binary download or pip), then:

```json
{
  "mcpServers": {
    "datadog": {
      "type": "stdio",
      "command": "<path-to>/datadog_mcp_cli",
      "args": [],
      "env": {
        "DD_SITE": "datadoghq.com"
      }
    }
  }
}
```

On first use, browser opens for Datadog OAuth.

**Smoke test**: "show recent logs for service X" or "list monitors that are alerting now."

### Gotchas
- **`DD_SITE` is required for non-US tenants.** Default is `datadoghq.com` (US1). Use `datadoghq.eu` (EU), `us3.datadoghq.com` (US3), `us5.datadoghq.com` (US5), `ap1.datadoghq.com` (AP1), or `ddog-gov.com` (Gov). Without the right value, every query 401/403s with no clear error.
- **OAuth vs API+APP keys.** OAuth is the default and works for personal use. Service-account orgs may prefer `DD_API_KEY` + `DD_APP_KEY` env vars instead - see the vendor docs.
- **Query syntax**: `avg:metric.name{tag:value} by {group}`. The MCP usually exposes a `search_datadog_docs` tool to help.
- **Log analysis**: `analyze_datadog_logs` runs structured queries over your logs - powerful for investigation.

---

## 8b. PagerDuty

**What it gives you**: Read your oncall schedule, list open incidents, ack/resolve from the CLI, query who's secondary on service X, page-count history.

**Package**: PagerDuty's [official MCP server](https://github.com/PagerDuty/pagerduty-mcp-server) (vendor-built, Python). Install with `pip install pagerduty-mcp-server` (or `pipx install` to keep your global Python clean). No single canonical npm wrapper - the Python package is what they ship.

```json
{
  "mcpServers": {
    "pagerduty": {
      "type": "stdio",
      "command": "pagerduty-mcp-server",
      "args": [],
      "env": {
        "PAGERDUTY_API_KEY": "<your-key>"
      }
    }
  }
}
```

API keys come from PagerDuty -> Profile -> User Settings -> API Access Keys. Use a personal key for personal use; org-level keys for shared automation.

If the official server doesn't fit your auth pattern (e.g. OAuth for an enterprise account, or you want a different language), the [community ecosystem](https://github.com/search?q=pagerduty+mcp+server&type=repositories) has alternatives - same env-var shape, different command path.

**Smoke test**: "who is oncall for service X right now?"

### Gotchas
- **Read-only by default.** Most MCPs default to read scopes. If you want ack/resolve, opt in explicitly.
- **Rate limits.** 60 RPS on REST API. Heavy queries (history walks) will throttle.
- **OpsGenie / Squadcast / Splunk On-Call.** Same shape - find a community MCP, plug in API key.

---

## 8c. Stripe

**What it gives you**: Read customers, charges, subscriptions, payouts, invoices. Useful for "show me churned customers this month" / "what was MRR last quarter" / "draft a refund for charge X."

**Package**: [Stripe Agent Toolkit](https://github.com/stripe/agent-toolkit) - vendor-built, includes an MCP server.

```json
{
  "mcpServers": {
    "stripe": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@stripe/mcp", "--tools=all"],
      "env": {
        "STRIPE_SECRET_KEY": "<your-restricted-key>"
      }
    }
  }
}
```

API keys come from Stripe Dashboard -> Developers -> API keys. **Use a restricted key** with read-only permissions for everything except the actions you want the agent to take. Never use the secret key directly.

**Smoke test**: "list my 5 most recent charges."

### Gotchas
- **Restricted keys are mandatory.** A full secret key gives the agent write access to everything (refunds, customer creation, charge captures). Scope per-tool.
- **Test mode keys**: prefix `sk_test_`. Live mode prefix `sk_live_`. Never paste `sk_live_` into a settings.json without reviewing what tools you've enabled.
- **Webhooks not covered**: the MCP is REST-only. For webhook event analysis, use the CLI (`stripe events resend`) or query event objects directly.

---

## 9. CLI tools (no MCP)

These work directly via Bash. No MCP setup, just install and authenticate.

| CLI | What for | Auth |
|-----|----------|------|
| `gh` | GitHub PRs, issues, code search | `gh auth login` |
| `gcloud` | Google Cloud resources | `gcloud auth login` + `gcloud auth application-default login` |
| `aws` | AWS resources | `aws configure` |
| `kubectl` | Kubernetes clusters | `kubectl config get-contexts` to verify |
| `terraform` | Infrastructure changes | Whatever your org uses; route changes via PR |
| `bq` | BigQuery queries | Comes with gcloud SDK |
| `psql` / `mysql` | Direct DB access | Connection strings in env |

### Why CLIs over MCPs for these
- `gh` is faster and more complete than any GitHub MCP.
- `gcloud`/`aws` MCPs exist but rarely match the CLI's coverage.
- `kubectl` needs direct cluster access that MCPs typically don't bridge well.
- `terraform` should always go through version control for audit trails.

---

## 10. Internal API Pattern (LinkedIn, Zillow, etc.)

For services with no official API or MCP, reverse-engineer the browser's network requests.

### Protocol
1. Find an **existing open-source library** wrapping the same API (PyPI, npm, GitHub search).
2. **Read its source** for endpoints, headers, magic values (decoration IDs, query IDs, etc.).
3. **Then build** - never trial-and-error first.

### Tool architecture (suggested)
```
tools/<service>/
  client.py      # API wrapper (requests/httpx)
  config.json    # Auth (cookies, API keys) + settings
  tracker.py     # State: dedup, favorites, change detection
  search.py      # CLI interface
```

### Auth patterns
- **Session cookies**: User copies from browser DevTools. Store in `config.json`. Expires periodically.
- **CSRF tokens**: Often paired with session cookie. Usually derived from another cookie value.
- **TLS fingerprinting**: Some sites (Zillow, Cloudflare-protected) block Python's default TLS. Use `curl_cffi` with `impersonate="chrome136"`.

### When to give up
- 3 failed approaches = question the premise. The service may be intentionally blocking automation.
- Search engines (Google, Bing) all CAPTCHA scrapers. Use Claude's `WebSearch` tool instead.

See [service-integration.md](./service-integration.md) for the full decision tree.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| MCP not showing up | Restart Claude Code after editing `~/.claude/settings.json` |
| Slack tokens expired | Re-extract `xoxc`/`xoxd` from browser (section 2) |
| Google OAuth broken | Delete the cached token file, re-authorize |
| SSL errors (Python, corporate proxy) | Install `truststore` |
| SQLite `disk I/O error` (macOS) | `com.apple.provenance` xattr - delete the file, let it recreate |
| MCP binary not found | Check `which <binary>` matches the path in settings.json |

---

## Quick Reference: What Goes Where

| Task | Tool |
|------|------|
| GitHub PRs/issues | `gh` CLI |
| Slack messages/search | Slack MCP |
| Jira tickets / Confluence | Atlassian MCP |
| Notion pages | Notion MCP |
| Datadog metrics/logs/monitors | Datadog MCP |
| Google Drive / Sheets / Docs | Google Workspace MCP |
| Google Calendar | Google Calendar MCP |
| Gmail | Gmail (or Google Workspace) MCP |
| GCP resources | `gcloud` CLI |
| AWS resources | `aws` CLI |
| Kubernetes | `kubectl` CLI |
| Infrastructure changes | `terraform` via PR (never CLI direct) |
| Web search | Claude's built-in `WebSearch` |
| Reverse-engineered API | Custom tool in `tools/<service>/` |

---

*Modular - skip any section that doesn't match your stack. Add your own at the bottom under a new section.*
