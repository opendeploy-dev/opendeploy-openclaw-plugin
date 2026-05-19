# Deploy attempt record

Every deploy attempt is a learning artifact. Write a structured record before
retrying, pausing, or reporting terminal success/failure. This is local,
redacted, and append-only by default; it is not uploaded unless the user or a
future CLI/backend command explicitly opts in.

## Files

Write both local forms when possible:

- `.opendeploy/attempts/<UTC-compact>-<project-or-repo>-<deployment-or-local>.json`
- `.opendeploy/deploy-attempts.jsonl`

The JSON file is the full record. The JSONL file gets one compact line per
attempt or retry so later tools can aggregate failures across repos.

Create `.opendeploy/attempts/` if needed. Keep files mode `0600` when they may
include log excerpts. Never put secret values in either file.
Before source upload, confirm the archive manifest does not include
`.opendeploy/attempts/` or `.opendeploy/deploy-attempts.jsonl`; if it does,
exclude those files before uploading application source.

## Backend sync

When the CLI exposes this surface, or when using the approved OpenDeploy API
escape hatch, also sync the redacted record to the backend attempt table:

- `POST /v1/deployment-attempts` creates or upserts by `record_id`.
- `PATCH /v1/deployment-attempts/<attempt-record-uuid>` updates a known row.
- `GET /v1/projects/<project-id>/deploy-attempts` lists project records.
- `GET /v1/deployments/<deployment-id>/attempt-records` lists records for a
  deployment.

Backend sync is never a deploy blocker. If the sync route fails, keep the local
JSON/JSONL record updated and continue with the deploy. Do not upload secret
values; the backend record stores env key names, redacted logs, classifications,
fixes, and final status.

## When to write

1. After local analysis and before cloud mutation: create a draft attempt record
   with repo structure, framework, language, package manager, planned
   service/dependency/env shape, and source evidence.
2. After each deployment reaches terminal `failed`, `cancelled`, or
   `rolled_back`: update the same record with logs, error category, root cause,
   and next action before retrying or asking the user.
3. After each fix/redeploy: append a `fixes[]` entry with what changed, the new
   deployment id, and the redeploy result.
4. Before final response: set `final.status` to `success`, `failed`, or
   `paused`, with live URL and caveats when known.

Do not wait until the end of a long deploy session. A crash, context compaction,
or user interruption should still leave the latest failed attempt on disk.

## Schema

Use this shape. Omit unknown values only when the evidence truly is unavailable;
prefer `null`, `[]`, or `"unknown"` over inventing data.

```json
{
  "schema_version": "deploy_attempt.v1",
  "record_id": "utc-timestamp-plus-short-random",
  "created_at": "2026-05-15T00:00:00Z",
  "updated_at": "2026-05-15T00:00:00Z",
  "agent": {
    "host": "codex|claude|cursor|openclaw|unknown",
    "skill_version": "0.0.2",
    "cli_version": "0.1.23"
  },
  "repo": {
    "path": "/absolute/local/path",
    "remote": "https://github.com/org/repo",
    "commit": "git-sha-or-null",
    "structure": {
      "root_files": ["package.json", "Dockerfile"],
      "service_roots": ["apps/web"],
      "workspace_files": ["pnpm-workspace.yaml"],
      "dockerfiles": ["Dockerfile", "apps/api/Dockerfile"],
      "compose_files": ["docker-compose.yml"],
      "ignored_candidates": [
        {"path": ".devcontainer", "reason": "dev tooling"}
      ]
    },
    "monorepo": false
  },
  "detected": {
    "framework": "Next.js",
    "language": "TypeScript",
    "package_manager": "pnpm",
    "runtime": "node",
    "deploy_mode": "autodetect|dockerfile|wrapper-image|static|unknown",
    "complexity": "static|framework|dockerfile|stateful|multi_service|storage_decision_required|multi_protocol"
  },
  "plan": {
    "project_name": "app-name",
    "services": [
      {
        "name": "web",
        "type": "web",
        "root": ".",
        "port": 3000,
        "build_command": "pnpm build",
        "start_command": "pnpm start",
        "dockerfile_path": null,
        "public": true
      }
    ],
    "dependencies": [
      {"type": "postgres", "required": true, "catalog_version": "15"}
    ],
    "volumes": [
      {"name": "data", "mount_path": "/data", "size": "5Gi", "required": true}
    ],
    "env": {
      "runtime_keys_needed": ["DATABASE_URL", "SESSION_SECRET"],
      "build_keys_needed": ["NEXT_PUBLIC_APP_URL"],
      "missing_keys": [],
      "generated_keys": ["SESSION_SECRET"],
      "secret_values_stored": false
    }
  },
  "deployments": [
    {
      "deployment_id": "uuid",
      "service_id": "uuid",
      "status": "failed",
      "phase": "build|deploy|runtime|edge|platform|analysis|unknown",
      "progress_percent": 10,
      "build_percent": 0
    }
  ],
  "failure": {
    "error_category": "missing_env",
    "root_cause": "DATABASE_DIRECT_URL was required by Prisma migrate deploy.",
    "log_excerpt": "redacted excerpt, capped",
    "evidence": [
      "schema.prisma references env(\"DATABASE_DIRECT_URL\")",
      "runtime log contains Environment variable not found: DATABASE_DIRECT_URL"
    ],
    "platform_issue": false
  },
  "fixes": [
    {
      "type": "env_patch",
      "description": "Set DATABASE_DIRECT_URL to the managed DATABASE_URL.",
      "files_changed": [],
      "env_keys_changed": ["DATABASE_DIRECT_URL"],
      "deployment_id": "retry-uuid",
      "result": "success"
    }
  ],
  "final": {
    "status": "success|failed|paused",
    "live_url": "https://service.opendeploy.run",
    "dashboard_url": "https://dashboard.opendeploy.dev/projects/...",
    "remaining_caveats": []
  }
}
```

## Error categories

Use one of these stable category keys:

| category | Use when |
|---|---|
| `analysis_miss` | Auto-plan picked wrong framework/service/root or missed required service/dependency |
| `unsupported_shape` | The app needs an unsupported protocol, sidecar, extension, or deploy mode |
| `source_archive` | Required source file missing, upload/bind failed, archive excludes needed paths |
| `build_command` | Build command, package install, compiler, lockfile, or regional mirror failure |
| `start_command` | Start command/CMD override missing, ignored, malformed, or not shell-wrapped |
| `missing_env` | Required runtime/build env key missing or syntactically invalid |
| `env_phase_mixed` | Runtime/build variables were mixed or put in the wrong field |
| `dependency_env` | Managed DB/cache env, credentials, DNS, placeholder, or readiness issue |
| `migration_missing` | DB schema/migration/bootstrap did not run or used the wrong command path |
| `port_mismatch` | Service port, `PORT`, `EXPOSE`, runtime listener, or readiness path disagree |
| `persistent_storage` | Required files/uploads/index/SQLite storage missing or volume not mounted |
| `quota` | Plan/add-on/resource quota blocked create/deploy/volume |
| `edge_ingress` | App healthy internally but public route/domain/edge returns 502/503 |
| `service_mapping` | Deployment logs/image/port/resource do not match the intended service |
| `platform_backend` | Gateway/backend/CLI returned inconsistent, unavailable, or not-wired behavior |
| `unknown` | Evidence is incomplete or contradictory |

Do not create project-specific categories. Put project-specific detail in
`root_cause` and `evidence`.

## Redaction

- Store env key names, never env values.
- Redact passwords, tokens, API keys, bind signatures, cookies, private keys,
  and authorization headers from log excerpts.
- Cap `log_excerpt` at roughly 4 KB. Prefer the shortest excerpt proving the
  category.
- If a local path or public repo URL is sensitive, store a redacted string and
  keep enough structure to preserve the deploy lesson.

## Updating JSONL

Append a compact, redacted summary line to `.opendeploy/deploy-attempts.jsonl`
whenever the full JSON record changes materially. Include:

- `record_id`
- `repo.remote` or redacted repo id
- `detected.framework`, `detected.language`, `detected.package_manager`
- `plan.services[].type/root/port`
- latest `deployment_id`
- `failure.error_category`
- latest `fixes[].type/result`
- `final.status`

The JSONL line should be enough to count recurring failures without opening the
full file.
