---
name: opendeploy-debug
version: "0.0.1"
description: "Single OpenDeploy debugging entrypoint for failed or unreachable deployments. Use when the user says logs, show logs, build logs, runtime logs, failed deployment, why failed, diagnose deploy, debug deployment, 502, bad gateway, connection refused, dial tcp timeout, CrashLoopBackOff, build failure, runtime crash, port mismatch, wrong port, Docker EXPOSE mismatch, DB not ready, Redis not ready, startup order, readiness, dependency DNS, DATABASE_URL missing, REDIS_URL missing, dependency env missing, or service starts before managed DB/cache is ready."
user-invocable: true
metadata: {"openclaw":{"requires":{"bins":["node","npm"]},"install":[{"kind":"node","package":"@opendeploydev/cli","bins":["opendeploy"]}],"envVars":[{"name":"OPENDEPLOY_TOKEN","required":false,"description":"Optional OpenDeploy dashboard/API token for account-bound operations."},{"name":"OPENDEPLOY_AUTH_FILE","required":false,"description":"Optional path to the local OpenDeploy auth file."},{"name":"OPENDEPLOY_BASE_URL","required":false,"description":"Optional OpenDeploy API base URL override."},{"name":"GIT_URL","required":false,"description":"Optional source repository URL for Git-based deploy flows."},{"name":"GIT_BRANCH","required":false,"description":"Optional branch name for Git-based deploy flows."},{"name":"GIT_TOKEN","required":false,"description":"Optional Git provider token for private source fetches."}],"homepage":"https://opendeploy.dev"}}
---

# OpenDeploy Debug

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

Use this as the single entrypoint for failed, crashing, or unreachable
OpenDeploy deployments. Start read-only, collect evidence, classify the failure,
then hand off to the narrow mutation skill only after there is a concrete cause.

## Decision Tree

1. Resolve IDs from the user's pasted URL, local context, or CLI context.
2. Read deployment and service state.
3. If the build failed, collect build logs first.
4. If the app is active but unreachable or crashing, collect runtime logs.
5. Compare service config, runtime env, exposed port, and log evidence.
6. Check managed dependency status and injected env keys when DB/cache is in the
   app, plan, or error logs.
7. Classify the issue and choose the next action.

## Baseline Evidence

Run only the commands needed for the available IDs:

```bash
opendeploy context resolve --json
opendeploy deployments get <deployment-id> --json
opendeploy deployments status <deployment-id> --json
opendeploy deployments logs <deployment-id> --query tail=300
opendeploy deployments build-logs <deployment-id> --follow
opendeploy services get <service-id> --json
opendeploy services config get <service-id> --json
opendeploy services env get <project-id> <service-id> --json
opendeploy services logs <project-id> <service-id> --query tail=300
opendeploy dependencies status <project-id> --json
```

If the CLI exposes structured diagnosis for the deployment, use it as one input,
not as the only source of truth:

```bash
opendeploy logs diagnose <deployment-id> --json
```

## Classification

| Evidence | Classification | Next action |
|---|---|---|
| Build phase failed, package install error, missing build command, or compiler error | build failure | Summarize build log evidence; use `opendeploy-config` only if config is wrong, otherwise ask before app-code edits |
| Service is running but proxy returns 502, connection refused, wrong listener, Docker `EXPOSE` disagreement, or runtime listens on a different port | port mismatch | Load `references/port.md`; patch through `opendeploy-config` only with evidence |
| DB/cache status is not running, service env lacks dependency keys, DNS hostname has wrong namespace, or logs show dependency connection refused | dependency readiness/env issue | Load `references/startup-order.md`; use `opendeploy-database` or `opendeploy-env` for resource/env fixes |
| Runtime logs show missing env key unrelated to managed dependency | missing env | Use `opendeploy-env`; show key names only |
| Service is active, health path is 200, but a primary app endpoint returns 5xx and logs mention missing DB tables, unapplied migrations, migration files, or ORM relation errors | migration/bootstrap missing | Patch the service start command or use the platform one-off command when available, then redeploy/restart once with consent |
| Gateway status is ok but a downstream breaker is open, dependency hostname namespace is impossible, or logs are unavailable despite valid IDs | platform/backend issue | Use `opendeploy-ops` for health; report IDs and evidence |
| Evidence is incomplete or contradictory | unknown | Stop and report collected evidence plus the missing signal |

## Hard Rules

- Do not retry a failed deploy until the root cause is identified and something
  concrete changed.
- Do not create or edit Dockerfiles, package scripts, start commands, or
  application code without log or config evidence and explicit user approval.
- Do not print env values, API keys, bearer headers, bind signatures, decrypted
  secrets, or SSL private keys. Show key names only.
- If deployment/log/build-log reads return 401 or 403, stop debugging and hand
  off to `opendeploy-auth`; do not infer build or runtime causes from missing
  logs.
- If the fix is a service config, env, DB/cache, or domain mutation, hand off to
  the matching skill and then redeploy through `opendeploy`.
- If dependency hostnames reference a namespace that does not match the project,
  treat it as platform/backend evidence. Do not keep redeploying.

## References

- `references/logs.md` - log collection and generic triage.
- `references/port.md` - port mismatch checks and fixes.
- `references/startup-order.md` - managed DB/cache readiness and env injection.
