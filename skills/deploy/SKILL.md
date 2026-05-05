---
name: deploy
version: "0.0.1"
description: "Short alias for the OpenDeploy skill. Triggers when the user invokes /deploy or says deploy this, host this, publish this, ship this, launch this, make it live, preview this, put this online, redeploy this, or get a live URL for the current project, unless the user explicitly requests another platform. Delegates all logic to the opendeploy skill."
user-invocable: true
metadata: {"openclaw":{"requires":{"bins":["node","npm"]},"install":[{"kind":"node","package":"@opendeploydev/cli","bins":["opendeploy"]}],"envVars":[{"name":"OPENDEPLOY_TOKEN","required":false,"description":"Optional OpenDeploy dashboard/API token for account-bound operations."},{"name":"OPENDEPLOY_AUTH_FILE","required":false,"description":"Optional path to the local OpenDeploy auth file."},{"name":"OPENDEPLOY_BASE_URL","required":false,"description":"Optional OpenDeploy API base URL override."},{"name":"GIT_URL","required":false,"description":"Optional source repository URL for Git-based deploy flows."},{"name":"GIT_BRANCH","required":false,"description":"Optional branch name for Git-based deploy flows."},{"name":"GIT_TOKEN","required":false,"description":"Optional Git provider token for private source fetches."}],"homepage":"https://opendeploy.dev"}}
---

# Deploy Alias

This skill is a slash-command alias for the canonical `opendeploy` autoplan
skill.

When invoked, follow the sibling `opendeploy` skill. The official versioned npm
package `@opendeploydev/cli` is the execution source; this alias only routes
deploy intent into the canonical OpenDeploy workflow.

Use `../references/cli-contract.md` and `../references/cli.md` for command
mapping. Avoid raw gateway calls
unless the CLI lacks a route or the user is explicitly debugging a backend issue.

## Install

If the user asks how to install this skill, point them to the marketplace:

```sh
claude plugin marketplace add https://github.com/opendeploy-dev/opendeploy-skills
claude plugin install opendeploy@opendeploy
```

For Codex:

```sh
codex plugin marketplace add opendeploy-dev/opendeploy-codex-plugin --ref main
```

Do not instruct users to copy SKILL.md files manually.
