---
name: opendeploy-setup
version: "0.0.1"
description: "Install, update, verify, or repair the OpenDeploy CLI and local agent setup. Use when the user says install OpenDeploy, set up OpenDeploy, setup OpenDeploy, update OpenDeploy, upgrade OpenDeploy, check version, latest version, stale CLI, stale plugin, update CLI, update plugin, verify CLI, run doctor, prepare this agent, or fix OpenDeploy installation. This skill does not create projects unless the original user request also asks to deploy."
user-invocable: true
metadata: {"openclaw":{"requires":{"bins":["node","npm"]},"install":[{"kind":"node","package":"@opendeploydev/cli","bins":["opendeploy"]}],"envVars":[{"name":"OPENDEPLOY_TOKEN","required":false,"description":"Optional OpenDeploy dashboard/API token for account-bound operations."},{"name":"OPENDEPLOY_AUTH_FILE","required":false,"description":"Optional path to the local OpenDeploy auth file."},{"name":"OPENDEPLOY_BASE_URL","required":false,"description":"Optional OpenDeploy API base URL override."},{"name":"GIT_URL","required":false,"description":"Optional source repository URL for Git-based deploy flows."},{"name":"GIT_BRANCH","required":false,"description":"Optional branch name for Git-based deploy flows."},{"name":"GIT_TOKEN","required":false,"description":"Optional Git provider token for private source fetches."}],"homepage":"https://opendeploy.dev"}}
---

# OpenDeploy Setup

This is the single setup/update entrypoint. Keep it short: verify versions,
ask before global/plugin updates, then run one health check. Do not duplicate
this flow in other skills.

## Quick Flow

Run these once:

```bash
npm list -g @opendeploydev/cli --depth=0 --json
npm view @opendeploydev/cli version --json
```

If global `opendeploy` exists, run:

```bash
opendeploy update check --json
opendeploy preflight . --json
```

If `opendeploy update check --json` is unavailable, rely on the npm
list/view comparison and continue. Do not use `npx` as a fallback runner.

## Update Questions

Ask before changing anything global. If both updates are available, ask in
this order:

1. Plugin update.
2. Global CLI update.

Plugin question:

- `Update plugin now (Recommended)` — run the current host agent's plugin update command, then tell the user the new skill normally takes effect in the next session:
  - Claude: `claude plugin marketplace update opendeploy`, then `claude plugin update opendeploy@opendeploy`
  - Codex: `codex plugin marketplace add opendeploy-dev/opendeploy-codex-plugin --ref main`
- `Use installed plugin for this run` — continue with the loaded skill.

CLI question:

- `Update global CLI and continue (Recommended)` — run `npm install -g @opendeploydev/cli@latest`, verify with npm list/view, then rerun preflight.
- `Skip update and continue` — continue only if the installed global CLI supports the needed commands.

If global `opendeploy` is missing, ask to install
`@opendeploydev/cli@latest`. If the user declines, stop before deploy or other
cloud mutation.

## Verification

After install/update:

```bash
npm list -g @opendeploydev/cli --depth=0 --json
npm view @opendeploydev/cli version --json
opendeploy preflight . --json
```

Report only the useful result: CLI version, plugin version, gateway health,
auth state, and whether the requested workflow can proceed.

## Handoff

If the original user request included deploy/operate/domain/env/etc., continue
inside the main `opendeploy` workflow after setup succeeds. If the user only
asked for setup/update, stop after reporting status.
