# Service Integration Decision Tree

How to connect to an external service. System-level - applies to any user, any service.

## Options (ranked by preference)

| Option | What it is | When to use | Example |
|--------|-----------|-------------|---------|
| **Existing MCP** | Pre-built MCP server (npm, pip, hosted) | Official or well-maintained server exists for the service | Notion, Slack, Gmail, Google Calendar |
| **Official API + custom tool** | Build a Python/Go script calling the service's documented API | Service has an API but no good MCP. Needs auth, pagination, domain logic. | Google Docs (no MCP, has REST API) |
| **Internal/undocumented API + custom tool** | Reverse-engineer what the browser/app sends | No official API. Service has a web frontend whose network requests can be replayed. | LinkedIn Voyager API |
| **CLI wrapper** | Use an existing CLI tool via Bash | Good CLI exists, no API/MCP needed | gh (GitHub), gcloud, kubectl, bq |
| **Web search proxy** | Use Claude's WebSearch at runtime | Content is public but no API/scraping path works (CAPTCHAs, JS rendering) | LinkedIn post search |
| **Browser automation** | Selenium/Puppeteer to control a real browser | Last resort. Needed for JS-rendered pages, complex auth flows, form submission. | N/A |

## Decision flow

```
Does an MCP server exist?
  YES -> Is it maintained + covers the use case?
    YES -> Use MCP
    NO  -> Fall through
  NO  -> Fall through

Does the service have an official API?
  YES -> Is auth feasible (OAuth, API key, cookie)?
    YES -> Build custom tool (tools/<service>/)
    NO  -> Fall through
  NO  -> Fall through

Does the service have a web frontend with inspectable network requests?
  YES -> Can you replay them without a full browser? (no JS rendering required, no CAPTCHA)
    YES -> Build custom tool using internal API
    NO  -> Fall through
  NO  -> Fall through

Is the data publicly accessible on the web?
  YES -> Use WebSearch at runtime (Claude searches, no script)
  NO  -> Fall through

Last resort: Browser automation (Selenium/Puppeteer)
  - Heavy, fragile, slow
  - Only for: form submission, JS-rendered content, complex auth
  - Consider if the ROI justifies the maintenance cost
```

## Activation rule

**When the user says "connect X" or "integrate X" - walk the decision tree above top-to-bottom BEFORE searching.** The default impulse is to search for existing integrations. Resist it. The tree exists because searching first leads to third-party detours (MCP servers, RapidAPI, Apify) when the direct path (internal API) is almost always correct for consumer web services.

## Lessons learned

### Auth patterns
- **OAuth**: Best when official. Store tokens, handle refresh.
- **Session cookies**: For internal APIs. User copies from browser DevTools. Expires periodically - the user must re-copy. Store in `config.json`, never hardcode.
- **CSRF tokens**: Internal APIs often require a CSRF token paired with the session cookie. Usually derived from a secondary cookie.
- **API keys**: Simplest. Store in config or env var.

### Internal API protocol
When building against an undocumented/internal API:
1. **Find an existing open-source library** wrapping the same API (PyPI, npm, GitHub search)
2. **Read its source** for endpoints, headers, magic values (decorationIds, queryIds, etc.)
3. **Then build** - never trial-and-error first

### Tool architecture
- Follow the `tools/<service>/` pattern: `client.py` (API wrapper), `config.json` (auth + settings), optional `tracker.py` (state), `search.py` (CLI).
- Guest/public endpoints (no auth) are valuable fallbacks.
- State tracking (what's new vs seen) turns a search tool into a monitoring tool. JSON file is enough.
- When a Python script can't do it (CAPTCHAs, JS rendering), Claude's built-in tools (WebSearch, WebFetch) are the right fallback.

### MCP vs custom tool
- MCP adds value when: tool is used across multiple AI clients, needs to be auto-discoverable, or someone else maintains it.
- Custom tool is better when: use case is specific, needs domain logic (filtering, tracking, dedup), or the MCP doesn't cover the workflow.
- Wrap as MCP later if the tool stabilizes and portability matters.
