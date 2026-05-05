---
name: opendeploy-context
version: "0.0.1"
description: "Resolve, save, or inspect OpenDeploy project/service/deployment context. Use when the user says existing project, saved IDs, project id, service id, deployment id, same service, same project, resume deploy, redeploy same service, avoid duplicate project, what project is this, or asks whether the current directory already has OpenDeploy context."
user-invocable: true
metadata: {"openclaw":{"requires":{"bins":["node","npm"]},"install":[{"kind":"node","package":"@opendeploydev/cli","bins":["opendeploy"]}],"envVars":[{"name":"OPENDEPLOY_TOKEN","required":false,"description":"Optional OpenDeploy dashboard/API token for account-bound operations."},{"name":"OPENDEPLOY_AUTH_FILE","required":false,"description":"Optional path to the local OpenDeploy auth file."},{"name":"OPENDEPLOY_BASE_URL","required":false,"description":"Optional OpenDeploy API base URL override."},{"name":"GIT_URL","required":false,"description":"Optional source repository URL for Git-based deploy flows."},{"name":"GIT_BRANCH","required":false,"description":"Optional branch name for Git-based deploy flows."},{"name":"GIT_TOKEN","required":false,"description":"Optional Git provider token for private source fetches."}],"homepage":"https://opendeploy.dev"}}
---

# OpenDeploy Context

## Invocation Preflight

If this skill is invoked directly, first run the global CLI version check unless
another OpenDeploy skill already did:

```bash
npm list -g @opendeploydev/cli --depth=0 --json
npm view @opendeploydev/cli version --json
opendeploy preflight . --json
```

If global is older than npm latest, hand off to `opendeploy-setup`. If the
user skips the update, continue with the installed global CLI when it supports
the needed commands. Do not run separate `--version`, `jq`, or raw `curl`
plugin probes after this preamble.

Context prevents duplicate projects/services and lets agents resume work. The
CLI keeps it in `.opendeploy/project.json` (no API keys, no env values).

```bash
opendeploy context resolve --json       # alias of `context status`; reads .opendeploy/project.json
opendeploy context save \
  --project <project-id> \
  --service <service-id> \
  --deployment <deployment-id> \
  --live-url <url> \
  --json
```

`context save` writes:

```json
{
  "project_id": "string",
  "service_id": "string",
  "deployment_id": "string",
  "live_url": "string",
  "saved_at": "ISO-8601"
}
```

After every successful first deploy, run `context save`. On redeploy, run
`context resolve` first to avoid duplicate `projects create`.

## URL paste shortcut

If the user pasted a dashboard URL, extract IDs from the URL instead of calling
`context resolve`. URL forms:

```text
https://dashboard.opendeploy.dev/projects/<PROJECT_ID>
https://dashboard.opendeploy.dev/projects/<PROJECT_ID>/services/<SERVICE_ID>
https://dashboard.opendeploy.dev/projects/<PROJECT_ID>/deployments/<DEPLOYMENT_ID>
```
