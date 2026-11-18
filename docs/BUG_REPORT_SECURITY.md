# Bug report spam: security and cleanup

The 4P table submits reports to a Cloudflare Worker at
https://mtg-bug-reporter.wajencz.workers.dev/report/4.

## Implemented

- TTS client: minimum title/description length, Discord-invite rejection,
  two-minute per-identifier cooldown and one in-flight request per reporter.
- GitHub Actions: closes matching Discord-invite-shaped reports on creation
  and, on first deployment or manual trigger, cleans up previously open ones.
  This does NOT prevent the upstream GitHub issue from being created.

## Still needed on the Cloudflare Worker

The client X-Report-Key is public, since TTS scripts are readable. It is not
an authentication method. The Worker source is outside this repository and
has NOT been changed here.

- Verify input type, length and content on the Worker before calling GitHub.
- Reject Discord invitation/link-only reports and known repeated payloads.
- Apply rate limits using the server-observed IP and a global quota.
- Do not trust player-supplied Steam IDs as authentication.
- Add server-validated bot challenges if the Worker remains publicly writable.
- Keep the GitHub API token only in the Worker's private environment.

Do not confuse a GitHub auto-closed issue with a request rejected before creation.
