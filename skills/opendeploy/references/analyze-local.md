# Local source analysis - opendeploy Step 2

Reference for Step 2: materialize the source, detect services, emit a fixed-schema `analysis.json`. **All client-side.** Forbidden routes for agent-first deployment: `/upload/analyze-only`, `/upload/analyze-from-upload`, `/upload/analyze-env-vars`, `/create-from-analysis`, and any `/analyze*` endpoint.

Default future path is CLI-owned analysis:

```bash
opendeploy analyze . --json
opendeploy deploy plan . --review --json
```

The rules below are the contract the CLI and fallback agent analysis must
match.

JSON-mode discipline (Backend CLAUDE.md section 3): emit **exactly** the fields listed in section 3 below. If a field is not confidently knowable, use empty string / empty array - never fabricate.

## 0. Second-pass review

Before any cloud mutation, run a second-pass review over the generated
analysis/plan. If the agent environment explicitly allows parallel agents, ask
an independent agent for this pass; otherwise do the review yourself and record
the result in the deploy plan.

Do not call this "outside voice" in user-facing output unless an independent
agent or reviewer actually ran it. In normal single-agent flows, call it
"self-review" or "plan review".

Challenge these points:

- Context source: pasted dashboard URL IDs, saved `.opendeploy/project.json`,
  and user intent must not conflict. If redeploying an existing project, require
  an existing service ID or ask whether to create a new service.
- DB/cache type missed or over-detected.
- Frontend build tooling is mistaken for the deploy runtime. Backend evidence
  such as `composer.json` + `artisan`, `manage.py`, `go.mod`, `Gemfile`,
  Maven/Gradle files, Phoenix/Laravel/Rails/Django app files, or server
  Dockerfiles wins over Vite/Webpack/SPA evidence.
- `DATABASE_URL`, `REDIS_URL`, `MONGODB_URI`, `MYSQL_URL`, `POSTGRES_URL`, or
  host/user/password aliases are not assigned to the service that needs them.
- `.env.example`, `.env.sample`, or placeholder values are treated as real
  user env.
- a root Dockerfile is present but the plan ignores it, or no Dockerfile exists
  and the plan assumes the agent should create one.
- Real user `.env` contains empty `DATABASE_URL` / `REDIS_URL` values that
  would override generated managed dependency env.
- Monorepo source root is too broad or points at the wrong app.
- Worker/web services are collapsed incorrectly.
- Docker `EXPOSE`, compose container port, framework default, and `PORT` env
  disagree.
- Dockerfile exposes multiple ports and the selected one is SSH/SMTP/raw TCP
  rather than the HTTP listener.
- Dockerfile `VOLUME`, compose `volumes:`, docs, or env keys indicate durable
  data paths but the platform has no persistent-volume primitive.
- Installer-lock/setup-complete flags appear without a plan to create the
  required admin/bootstrap state.
- DB-backed framework migrations are needed but not planned before first
  traffic. Check for `manage.py migrate`, Rails migrations, Laravel
  `php artisan migrate`, Prisma/Drizzle/Alembic commands, and similar.
- Late-bound URL/domain env (`APP_URL`, `BASE_URL`, `ROOT_URL`, `SITE_URL`,
  `PUBLIC_URL`, `CANONICAL_URL`, `SERVER_URL`, `WEB_URL`, or nested
  `__ROOT_URL` / `__DOMAIN` variants) is required but not planned.
- Source archive excludes would remove required non-secret source files, such
  as a project-owned `build/` directory or a credential-free `.npmrc`.
- `docker-compose depends_on` references DB/cache services that were not mapped
  to managed dependencies.
- A generated dependency hostname has a namespace suffix that does not match
  the project namespace expected for the app service.

If any item is blocking, stop before setup and ask or fix the plan. Do not
paper over uncertainty with a deploy-and-see loop.
Analyzer mistakes are not blocking by themselves. If direct source evidence
clearly corrects the service split, runtime, port, dependencies, or deploy mode,
rewrite the plan and continue. Use a structured question only when the fix needs
a new consent gate that is not already covered.

### Evidence ledger

For each service, record the evidence behind the selected deploy shape. Keep it
compact; the goal is to make the plan auditable, not verbose.

```json
{
  "service": "web",
  "decision": "port",
  "value": 3000,
  "evidence": "Dockerfile EXPOSE 22 3000; 22 is SSH, 3000 is HTTP web UI"
}
```

Required evidence categories:

- selected source root
- deploy mode (`autodetect`, existing `Dockerfile`, image, or other)
- selected HTTP port and ignored secondary ports
- build/start command or Dockerfile `CMD`/`ENTRYPOINT`
- dependency decision and env aliases
- persistent filesystem/object-storage requirement
- required archive inclusions/exclusions
- late-bound public URL env keys

If evidence is missing for a category that affects first deploy success, ask
before mutation or mark it as a blocking issue.

### Complexity classification

Assign the same coarse class used by `deploy-plan.md`:

- `static`
- `framework`
- `dockerfile`
- `stateful`
- `multi_service`
- `storage_decision_required`
- `multi_protocol`

The class controls review depth. For example, a `dockerfile` app requires
Dockerfile inspection before service creation; a `stateful` app requires
dependency readiness plus env read-back; a `storage_decision_required` app
needs an explicit storage choice before mutation.

---

## 1. Materialize source to a local workdir

```bash
WORKDIR=$(mktemp -d)
case "$SOURCE_KIND" in
  git)    git clone --depth=1 ${GIT_BRANCH:+-b "$GIT_BRANCH"} "$GIT_URL" "$WORKDIR" ;;
  zip)    unzip -q "$ZIP_PATH" -d "$WORKDIR" ;;
  folder) WORKDIR="$SOURCE_PATH" ;;
esac
```

### Files to enumerate

One pass, do **not** recurse into `node_modules`, `.git`, `dist`, `target`, `vendor`, `__pycache__`, `.venv`.

```
package.json, pnpm-lock.yaml, package-lock.json, yarn.lock, bun.lock, bun.lockb
pnpm-workspace.yaml, turbo.json, lerna.json, nx.json, .npmrc
requirements.txt, pyproject.toml, Pipfile, setup.py
go.mod, Cargo.toml, pom.xml, build.gradle(.kts), composer.json, Gemfile
Dockerfile, */Dockerfile, */*/Dockerfile, docker-compose.y?(a)ml, Procfile
.env, .env.example, .env.sample, .env.template
next.config.{js,mjs,ts}, vite.config.*, nuxt.config.*, svelte.config.*,
  astro.config.*, remix.config.*, angular.json
README* (first 200 lines only)
```

Real deploy env override files (`.env.local`, `.env.*.local`, and
environment-specific secret files) are not source analysis inputs. Top-level
`.env` is special: in PHP/Symfony/Laravel-style apps it may be committed,
non-secret source required by bootstrap, but OpenDeploy smart archives exclude
`.env` / `.env.*` for safety. Read `.env` only enough to classify whether it is
required safe defaults or secret config. Never copy real env values into
`analysis.json`. If it is required and safe, plan to recreate it in the
Dockerfile/entrypoint from literal non-secret defaults.

---

## 2. Multi-service detection

Pick the first matching rule:

1. **`docker-compose.y?ml` present** -> build a service graph; do not mirror
   every top-level `services:` entry as an OpenDeploy app service. Extract
   `image`, `build.context`, `ports`, `environment`, `depends_on`, `profiles`,
   `command`, and `restart`.
   - Repo-local `build:` services with a web/worker/scheduler role are app
     services.
   - Entries whose image/name matches `postgres | mysql | mariadb | mongo |
     redis | valkey | rabbitmq | clickhouse | elasticsearch | meilisearch |
     minio` are dependencies, not build services, when OpenDeploy exposes a
     compatible catalog item.
   - Ignore dev/test/tooling entries unless the user explicitly asks for them:
     `.devcontainer`, `devcontainer`, `test`, `e2e`, `mock`, `storybook`,
     `docs`, `benchmark`, `seed`, `setup`, one-shot init jobs, and services
     enabled only by dev/test profiles.
   - `image:`-only entries with no repo-local `build:` are prebuilt sidecars.
     Classify them as `prebuilt_image_sidecar`; do not attempt to build them
     from the source repo. If the sidecar is essential and OpenDeploy does not
     expose image-service support in the current CLI, surface that as a support
     gap before mutation.
2. **Procfile present** -> `web` is the public HTTP service; `worker`, `queue`,
   `sidekiq`, `celery`, `scheduler`, and `clock` are worker/cron services with
   no public domain unless source evidence proves they expose HTTP.
3. **Monorepo markers** (`pnpm-workspace.yaml`, `package.json#workspaces`,
   `turbo.json`, `lerna.json`, `nx.json`) OR multiple top-level `Dockerfile`s
   -> each workspace package that has its own `Dockerfile`, server entrypoint,
   or `scripts.start` is a service.
4. Otherwise -> single service named `$PROJECT_NAME`.

Classify the monorepo shape:

- **Isolated monorepo**: sub-apps do not import local workspace packages. Use
  the app subdirectory as the service source/root.
- **Shared workspace**: workspace packages under `packages/*`, local
  `workspace:*` dependencies, TypeScript path aliases, or Turborepo/Nx shared
  tasks are required. Upload from repo root and use filtered build/start
  commands (`pnpm --filter <pkg> build`, `turbo run build --filter=<pkg>`,
  etc.). Do not set a narrow root that hides shared packages.

For multi-service plans, emit one public entrypoint unless the user explicitly
asks for multiple public services/domains. Workers and cron services are
internal by default.

---

## 3. Per-service schema

Emit one object per service. For multi-service, wrap as `{"services":[...]}`. Save to `$WORKDIR/.opendeploy/analysis.json`.

```json
{
  "name": "api",
  "source_path": "./services/api",
  "language": "typescript",
  "language_version": "20",
  "framework": "nextjs",
  "build_tool": "pnpm",
  "package_manager": "pnpm",
  "package_manager_version": "9.7.1",
  "lockfile": "pnpm-lock.yaml",
  "dependency_resolution": "locked",
  "project_type": "web",
  "port": 3000,
  "entry_point": "src/server.ts",
  "output_directory": ".next",
  "scripts_build": "pnpm build",
  "scripts_start": "pnpm start",
  "database_type": "postgres",
  "dependencies": ["postgres", "redis"],
  "runtime_vars":  [{"name":"DATABASE_URL","required":true,"default":""}],
  "build_time_vars":[{"name":"NEXT_PUBLIC_API_URL","required":false,"default":""}]
}
```

### Field-by-field rules

**`port`** - in priority order:
1. Dockerfile `EXPOSE <N>` -> the HTTP listener port. If there are multiple
   ports, prefer documented/common HTTP ports (`80`, `8080`, `3000`, `3001`,
   `4173`, `5000`, `8000`, `8081`) over SSH/SMTP/raw TCP ports (`22`, `2222`,
   `25`, `465`, `587`, database ports). If still ambiguous, ask.
2. compose `ports: ["host:container"]` -> `container`.
3. Framework default:
   - Next.js / Nuxt / Rails -> `3000`
   - Vite `preview` -> `4173`
   - Django -> `8000`
   - Flask -> `5000`
   - Spring Boot / Go `net/http` / Rust Actix -> `8080`
   - Laravel/PHP -> ask unless repo config, Dockerfile, compose, Procfile, or
     `APP_PORT` gives a clear HTTP listener. Do not use Vite preview `4173`
     for Laravel/PHP apps where Vite is only the asset bundler.
4. Ambiguous -> ask the user; do not guess.

OpenDeploy first deploy exposes one HTTP port. If the app also exposes SSH,
SMTP, metrics-only, database, or other raw TCP ports, surface the HTTP-ingress
behavior before mutation. Disable or leave secondary protocols inactive only
with user approval.

**`language` / `framework`** - derive from manifest, never from file extensions alone:
- `package.json.dependencies.next` -> `framework: nextjs`, `language: typescript` (if `tsconfig.json`) else `javascript`.
- `pyproject.toml.project.dependencies` containing `django` / `fastapi` / `flask` -> corresponding framework.
- `manage.py` at repo root -> `framework: django` even if `pyproject.toml` is
  missing or doesn't list `django` directly (Saleor-style layouts where Django
  is a transitive dependency).
- `go.mod` present -> `language: go`; framework from imports (e.g. `gin-gonic/gin` -> `gin`).
- `Cargo.toml` -> `language: rust`; framework from deps.
- `pom.xml` / `build.gradle*` -> `language: java`; framework from deps.
- `composer.json` plus `artisan` or `laravel/framework` -> `language: php`,
  `framework: laravel`. If `package.json` also has Vite, classify Vite as
  `build_tool`, not the runtime framework.
- `composer.json` with `symfony/*` -> `language: php`, `framework: symfony`.
- `Gemfile` plus `config/application.rb` containing `Rails::Application` ->
  `framework: rails`.
- Generic `composer.json` -> `language: php`; framework from Composer deps.

**Skill-side framework fallback.** If `opendeploy analyze --json` returns
`framework: ""` for a service, do not accept the empty value. Re-derive locally
using the rules above and record it in the deploy plan with
`framework_source: "skill_fallback"`. The local CLI auditor has been observed
returning empty `framework` for clearly-Django apps (settings module + manage.py
+ uvicorn ASGI Dockerfile), and a missing framework value cascades into missing
migration plans, missing default ports, and missing bootstrap warnings.

**`runtime_vars`** - union of:
- All keys in `.env.example` / `.env.sample` / `.env.template`.
- Grep hits for these patterns in source (just grep, do not parse AST):
  - JS/TS: `process.env.VAR_NAME`
  - Python: `os.getenv("NAME")`, `os.environ["NAME"]`, `os.environ.get("NAME")`
  - Go: `os.Getenv("NAME")`
  - Rust: `std::env::var("NAME")`, `env!("NAME")`
  - Ruby: `ENV["NAME"]`
  - PHP: `getenv("NAME")`, `$_ENV["NAME"]`
  - Shell: `$NAME` / `${NAME}` in `entrypoint.sh` / `docker-entrypoint.sh`
- `environment:` keys from each compose service.

Mark `required: true` only when:
- No default value in `.env.example` / `.env.sample` / `.env.template`, AND
- No fallback in code (e.g. `process.env.FOO || "bar"` -> `required: false`).

When unsure, `required: false` with `default: ""`.

Also classify env keys by deploy impact:

- `startup_critical`: referenced during module import, framework/bootstrap
  setup, top-level client/SDK construction, auth strategy registration, direct
  string method calls without fallback, or URL construction. These keys can
  crash the process before the HTTP server listens, so they must be resolved
  before the first deployment.
- `dependency_provided`: expected from managed DB/cache/storage dependencies.
- `generated_app_secret`: safe for the agent to generate locally with consent
  (session secret, encryption secret, basic-auth password, bootstrap password).
- `late_bound_url`: public URL/domain keys that need a temporary boot value or
  a planned post-success patch plus redeploy.
- `feature_optional`: only used inside route/job handlers or optional feature
  paths and safe to leave unset when source evidence shows the app guards that
  path.

For Node/JS services, startup-critical patterns include `process.env.KEY`
followed by a method call, `new URL(process.env.KEY)`, top-level provider
client constructors, and top-level auth strategy registration. Use the same
principle for other languages: env consumed while importing/configuring the app
is boot-critical; env consumed only when a feature is invoked is optional.

**`database_type`** - primary DB field; pick first non-cache match
for backwards compatibility:
1. Compose DB-image (`postgres` / `mysql` / `mariadb` -> `mysql` / `mongo` -> `mongodb` / `redis` / `valkey` -> `redis`).
2. Manifest deps:
   - Postgres: `pg`, `psycopg`, `psycopg2`, `psycopg2-binary`, `dj_database_url`,
     `sqlalchemy` with `postgres://`, `gorm.io/driver/postgres`, `lib/pq`,
     `tokio-postgres`, `sequelize` with `dialect:'postgres'`.
   - MySQL: `mysql2`, `pymysql`, `mysql-connector-python`, `gorm.io/driver/mysql`, `go-sql-driver/mysql`.
   - MongoDB: `mongoose`, `mongodb`, `pymongo`, `motor`, `mongo-driver`.
   - Redis: `redis` (npm/py), `ioredis`, `go-redis/redis`, `redis-rs`.
3. Empty string if none.

**Skill-side dependency fallback.** If `opendeploy analyze --json` returns
`dependencies: []` or `services[*].dependencies: []`, do not accept it for any
service whose framework is one of `django` / `rails` / `laravel` / `phoenix` /
`saleor` / `medusa`. Run a direct grep on the source for the dep markers above
plus `psycopg`, `redis`, `pymongo`, `pymysql`, `dj_database_url`,
`celery[broker=redis]`, and `CACHE_URL` / `REDIS_URL` references in settings.
For any hit, add a synthetic dependency entry to the deploy plan. If deploy
consent already covers managed dependencies, provision the managed dependency
before service creation and continue. Otherwise ask with a structured question
whose recommended option is to add the managed dependency first.
Deploying a Django/Rails-class app without a planned database is the single
most common preventable first-deploy failure.

**`build_time_vars`** - anything matching:
- Prefix `NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `PUBLIC_`, `NUXT_PUBLIC_`, `EXPO_PUBLIC_`.
- Any var referenced in `scripts.build` / Dockerfile `ARG` / CI build command.

Only key names and requirement/default metadata come from `.env.example`,
`.env.sample`, or `.env.template`. Their values are never user-approved deploy
values and must not be copied into `build_variables` or `runtime_variables`.

Runtime/build split:

- `runtime_variables`: DB/cache/storage connection values, server-side
  secrets, app bootstrap credentials, `PORT`, runtime-only framework config,
  and late-bound public URL/domain keys.
- `build_variables`: Dockerfile `ARG` values, variables read by build scripts,
  and public client compile-time prefixes (`NEXT_PUBLIC_`, `VITE_`,
  `REACT_APP_`, `PUBLIC_`, `NUXT_PUBLIC_`, `EXPO_PUBLIC_`).
- Do not mirror all keys between the two maps. A key belongs in both only when
  repo evidence shows it is consumed by both a build step and the running
  process. Record that reason in the plan.
- Dependency env from managed DB/cache belongs in `runtime_variables` unless a
  build step explicitly connects to the dependency. Avoid build-time DB access
  by default because it makes clean builds depend on live runtime services.

If required env keys remain unresolved after managed dependency env and
generated app credentials, surface an env-source question before service
creation:

- local real `.env` exists -> recommend syncing that `.env`
- no local real `.env` -> recommend manually setting required vars
- optional-only keys -> allow continuing without them

If startup-critical provider credentials are missing and the app can still show
the core UI with fake provider values, ask before setting boot-safe
placeholders. Present this as a demo/startup aid, not as a real integration
setup, and report that the related feature will need real env values plus a new
deployment before it works.

Never recommend uploading `.env.example` values.

**`package_manager` / `lockfile` / `dependency_resolution`** - make clean cloud
builds deterministic before mutation:
- Read `package.json.packageManager` when present, for example
  `pnpm@9.7.1`, `npm@10.x`, `yarn@4.x`, or `bun@1.x`.
- Record the matching lockfile:
  `pnpm-lock.yaml`, `package-lock.json`, `yarn.lock`, `bun.lock`, or
  `bun.lockb`.
- If a Node/JS service has no lockfile, set
  `dependency_resolution: "unlocked"` and add a blocking review item before
  cloud mutation. Ask whether to generate a lockfile, proceed knowing a clean
  cloud build may resolve newer packages, or stop.
- Inspect Dockerfile package-manager commands. If the Dockerfile uses unpinned
  Corepack or latest-style commands such as `corepack use pnpm`,
  `corepack prepare pnpm@latest`, or a bare package-manager install while
  `package.json.packageManager` pins a version, ask before patching the
  Dockerfile to the pinned version. Prefer pinning the package manager to the
  repo declaration over upgrading the base image unless repo evidence requires
  a newer runtime.
- Treat package-manager mismatch as a pre-build issue, not a cloud retry
  issue. Do not wait for OpenDeploy to spend build minutes discovering that
  Node, Corepack, and the package-manager version are incompatible.

**`dependencies`** - list of all DB/cache types this service needs. Populate
with every unique detected type, not just `database_type`:
- `database_type` is non-empty, include it.
- Manifest deps or env keys identify additional engines, include each one.
- Multi-service compose has `depends_on` pointing at DB/cache services - include each referenced type.
- Compose contains DB/cache image services that are consumed by the app - include each type.

---

## 3.5 Deploy env collection - submit values to the platform API

This step is separate from source analysis. It exists so automatic deploys can
pick up local runtime/build configuration without uploading secret files.

Allowed behavior:

- Read real env files only to build deployment override maps.
- Submit the resulting key/value pairs through the CLI as `runtime_variables`
  / `build_variables` during service create, or via `opendeploy services env
  patch/reconcile` for env rotation.
- Keep local override files mode `0600`.
- Log and report only key names and counts, never values.

Forbidden behavior:

- Do not write real env values to `$WORKDIR/.opendeploy/analysis.json`.
- Do not include real env files in the source ZIP.
- Do not write real env values to `~/.opendeploy/logs/*`.
- Do not submit values from `.env.example`, `.env.sample`, or `.env.template`
  as runtime or build env. They are examples and schema hints only, even when
  the key has a public build prefix such as `VITE_*`.

Collect from these files when present, later files overriding earlier files:

```text
.env
.env.local
```

If the project has its own dotenv parser in its toolchain, prefer that parser.
Otherwise parse standard `KEY=VALUE` dotenv lines, ignoring blank lines,
comments, and malformed keys. Split variables with public build prefixes into
`user_build_overrides.json`; all others go to `user_overrides.json`. Do not
write the same flat env object to both files. When a key must be mixed, include
it in both files only after recording the build-time and runtime evidence.

If only example files contain a required public build-time key, ask the user for
real values or confirm that the app can build with the key absent. Never present
"upload `.env.example` values" as the recommended option.

```bash
umask 0077
: > user_overrides.json
: > user_build_overrides.json
chmod 600 user_overrides.json user_build_overrides.json

# The agent should materialize these JSON files as flat objects:
#   user_overrides.json        -> runtime env values submitted to the platform
#   user_build_overrides.json  -> build-time env values submitted to the platform
#
# Public build prefixes:
#   NEXT_PUBLIC_, VITE_, REACT_APP_, PUBLIC_, NUXT_PUBLIC_, EXPO_PUBLIC_
#
# Example shape only; never print values:
#   {"DATABASE_URL":"postgres://...", "SESSION_SECRET":"..."}
```

Delete the two override files after the deploy attempt completes, success or
failure. They are local transport files only.

---

## 4. Decision: does the project need a DB? (Step 2.5)

Create DB/cache dependencies in Step 3.2 if **any** of these hold:

- `analysis.database_type` in {`postgres`, `mysql`, `mongodb`, `redis`}.
- `analysis.dependencies[]` contains any of {`postgres`, `mysql`, `mongodb`, `redis`}.
- Any `runtime_vars[].name` matches `DATABASE_URL | MYSQL_* | POSTGRES_* | PG_* | REDIS_URL | MONGO*`.
- Section 2's compose parse found a DB-image service (`postgres|mysql|mariadb|mongo|redis|valkey|...`).

Mapping to `dependency_id` values for `POST /dependencies/create`:

| detected | `dependency_id` |
|---|---|
| postgres, postgresql | `postgres` |
| mysql, mariadb | `mysql` |
| mongodb | `mongodb` |
| redis, valkey | `redis` |

This mapping is internal planning only. User-facing choices must use engines
from `opendeploy dependencies list --json`. Do not show "Managed MariaDB" when
the planned OpenDeploy dependency is `mysql`; label it "Managed MySQL" and, if
helpful, say the app's MariaDB-compatible mode will use OpenDeploy MySQL. Do
not show "Managed SQLite"; SQLite is a local file and belongs in the
volume/storage decision. For SQLite, the user-facing option label should be
`Use SQLite on OpenDeploy volume`.

ClickHouse, RabbitMQ, Elasticsearch, Meilisearch, and MinIO may be detected
from compose or env names, but they are not OpenDeploy managed dependencies in
this skill version. Treat them as external services: surface a warning and ask
for user-provided env values rather than creating a managed dependency.

Create one dependency per unique detected type in Step 3.2 (no `service_id`);
reuse each dependency's `env_vars` in every consumer service's Step 3.3 body.
If multiple services share the same engine, create that engine once. If an app
needs both a SQL database and Redis, create both and merge both env maps.

If no signal triggers -> this is a no-op. Do NOT provision "just in case" - it burns region quota.

---

## 4.5 Persistent storage and bootstrap scan

Before packaging, scan for persistent filesystem expectations:

- Dockerfile `VOLUME`
- compose `volumes:`
- docs mentioning durable data directories
- env keys ending in `_DATA_DIR`, `_UPLOAD_DIR`, `_STORAGE_PATH`,
  `_MEDIA_ROOT`, `_REPO_ROOT`, or similar

If persistent storage is needed, pause and ask for the OpenDeploy storage
strategy. Available options:

- Attach an OpenDeploy volume via `opendeploy-volume` (recommended for local
  uploads, backups, media, SQLite, file queues, on-disk repo storage, indexes,
  or any app that writes durable data to a fixed filesystem path). For a
  **new service** in the current deploy, include `volumes` inline in
  `service.json` on `services create` (StatefulSet from the start, no
  downtime). For an **existing service**, route to `opendeploy-volume`; the
  first volume on an existing service triggers a destructive
  Deployment→StatefulSet conversion with ~30s downtime.
- Configure the app's supported object-storage/media env when the app is
  already designed for external object storage and only needs S3/R2/Spaces env.
- Continue with ephemeral local files only after the user explicitly accepts
  data loss for those paths on restart/redeploy/reschedule.
- Review details, or pause before mutation.

If the user chooses external object storage, collect the secret source before
any cloud resource creation. Use a structured secret question when available,
or ask for a local 0600 env/body file path. The agent should run the
OpenDeploy `services env patch --body ... --confirm-env-upload` commands after
services exist; do not ask the user to paste or execute CLI command blocks as
the normal path.

Never auto-attach a volume — `opendeploy-volume` carries its own
workload-conversion confirmation. Do not call the deployment a preview, and
do not suggest a competing platform unless the user asks for alternatives.

Also scan for installer/bootstrap bypass flags such as `INSTALL_LOCK`,
`SETUP_DONE`, `SKIP_INSTALL`, `DISABLE_INSTALLER`, and app-specific
setup-complete flags. Do not set them automatically unless the deploy plan also
creates the needed admin/bootstrap state or the user approves that setup
choice.

For DB-backed frameworks, scan for migration/bootstrap commands before first
deploy:

- Django: `manage.py`, `python manage.py migrate`, `collectstatic`
- Rails: `rails db:migrate`
- Laravel: `php artisan migrate --force`
- Prisma/Drizzle: `prisma migrate deploy`, `drizzle-kit migrate`
- Alembic: `alembic upgrade head`

If a fresh managed DB is created, include a migration path in the deploy plan
before service creation. Prefer a platform one-off/release command when
available; otherwise ask before adding a start-command migration prefix. If the
DB already has user data, ask before running migrations.

Scan migrations and optional plugins for database extensions before spending a
build:

- SQL `CREATE EXTENSION`
- Rails `enable_extension`
- strings such as `pgvector`, `vector`, `postgis`, `citext`, `uuid-ossp`, and
  `pg_trgm`

If the app needs an extension that the selected OpenDeploy dependency does not
explicitly expose, record it as a deploy-plan risk. When the feature is an
optional plugin/module, make "disable that optional feature and continue" the
OpenDeploy-first recommendation after source-edit approval. Otherwise engage
OpenDeploy support instead of retrying the same migration.

For late-bound app URL env, record the key names so Step 9 can patch them after
the live URL is known. Do not invent app-specific keys; only patch keys that the
repo itself references.

Scan for a documented health/readiness endpoint before service creation. Prefer
repo evidence such as `/health`, `/healthz`, `/ready`, `/status`, `/srv/status`,
or framework-specific status handlers over `/` when the root path runs setup,
auth, redirects, or expensive application code.

If Dockerfile or build scripts use broad `COPY . .` / `ADD .`, inspect the
archive manifest for local agent metadata and workspace state. Exclude
`.agents/`, `.claude/`, `.codex/`, `.opendeploy/`, `.gstack/`, `.git/`,
dependency caches, and build outputs before upload unless a project-owned source
file in one of those paths is explicitly required.

## 5. Package the source for upload (Step 4)

**Format: ZIP only.** The backend (`project-service/internal/handlers/upload.go`) uses `archive/zip` exclusively; tar / tar.gz is rejected at extraction. Keep `source_path` per service so Step 4 can zip the right subfolder for monorepos.

```bash
SRC_ZIP="$WORKDIR/.opendeploy/$SVC_NAME.zip"
mkdir -p "$(dirname "$SRC_ZIP")"

# zip from inside the service subfolder so archive paths are flat.
# Env/credential files are deployment inputs, not source artifacts.
# If a framework needs a safe committed `.env`, recreate it in Dockerfile/entrypoint.
(cd "$WORKDIR/$SVC_SOURCE_PATH" && \
  zip -qr "$SRC_ZIP" . \
    -x '*.git/*' 'node_modules/*' 'dist/*' \
       'target/*' '.venv/*' '__pycache__/*' '*.pyc' \
       '.opendeploy/*' \
       '.env' '.env.*' '.pypirc' '.netrc' \
       '*.pem' '*.key' 'id_rsa' 'id_rsa.pub' 'id_ed25519' 'id_ed25519.pub' \
       'credentials.json' 'service-account*.json' '*kubeconfig*')
```

Do not rely on uploading top-level `.env`; the CLI smart archive excludes it
for safety. Symfony-family and some Laravel/PHP apps commit `.env` as
non-secret defaults, and bootstrap code may call
`Dotenv::loadEnv('/app/.env')`, which fails if the file is missing. If `.env`
is referenced by bootstrap/Dockerfile and contains only safe defaults such as
`APP_ENV` / `APP_DEBUG`, recreate those lines inside the Dockerfile or
entrypoint, for example `RUN printf 'APP_ENV=prod\nAPP_DEBUG=0\n' > .env`.
If it contains credentials, tokens, URLs with passwords, private keys, or
user-specific secrets, keep it excluded and upload those values through service
env after explicit consent.

Do not blanket-exclude top-level `build/`. Many languages use `build/` as
source or generator input. Exclude a build-like directory only when project
evidence says it is generated output for this repo. Keep `.npmrc` when it
contains build configuration only. If `.npmrc` contains auth material
(`_authToken`, `_password`, `username=`, `//registry...:_auth`, etc.), treat it
as a secret: ask for explicit consent or strip/rewrite it before upload.

Before upload, inspect the manifest:

```bash
unzip -l "$SRC_ZIP" | sed -n '1,120p'
```

Check Dockerfile `COPY` / `ADD` sources, BuildKit bind mounts, Makefile targets,
`go generate`, package scripts, and language manifests against the ZIP. If a
non-secret required source file is missing, rebuild the archive before upload,
except for top-level `.env` / `.env.*`: those are intentionally stripped by the
OpenDeploy smart archive and should be recreated from safe static defaults in
the Dockerfile or entrypoint when the framework requires them.
If the build needs Git metadata (`git describe`, `.git/` bind mount, commit
version), do not upload `.git` by default; prefer a build variable such as
`GIT_COMMIT`, `APP_VERSION`, or `SOURCE_VERSION` derived from `git rev-parse`
and record that choice in the plan. CLI `0.1.19+` surfaces this as
`archive_manifest.git_metadata`; treat `.git` bind mounts as blocking until
the plan has a safe replacement.

The archive path must end in `.zip`. Some backend readers reject or mishandle
valid ZIP bytes with a non-`.zip` suffix.

If the user supplied a ZIP directly, inspect it before upload. If it contains
real env or credential files matching the exclusion list above, do **not**
silently abort. Surface an `AskUserQuestion`:

> Question: `"This ZIP contains files that look like real secrets. Continue?"`
>
> Body (verbatim — list the matched paths, one per line, never the contents):
> > The archive at `<ZIP_PATH>` contains the following files that match
> > opendeploy's secret-exclusion list. They will be uploaded as-is to the
> > build pipeline if you continue:
> >
> > `<MATCHED_PATHS>`
> >
> > Recommended: re-zip the source with these excluded, or hand the skill a
> > directory path so it can build a clean archive itself.
>
> Options:
> - `Re-zip without these files` — print a `zip -d <ZIP_PATH> <files>` one-liner the user can run, then exit `0`. Do **not** mutate the user's ZIP from the skill.
> - `Hand me a directory instead` — surface a follow-up `AskUserQuestion` collecting a `SVC_SOURCE_PATH`, then jump back to the directory-zip block above.
> - `Upload as-is, I know what's in there` — emit `od_log warn analyze.unsafe_zip_accepted matched "<MATCHED_PATHS>"` and proceed with the upload. Surface the deploy target line (Execution rule 12) so the user has a final Ctrl-C window before mutation.
> - `Cancel` — emit `od_log info analyze.unsafe_zip_cancelled` and exit `0`.

The default behaviour (no answer, non-interactive context) is **reject** —
print the matched paths, the three options above, and exit `1` so a wrapper
agent can re-drive the prompt.
