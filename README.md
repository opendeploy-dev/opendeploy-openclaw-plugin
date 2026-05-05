<a href="https://opendeploy.dev/"><img src="https://oss.opendeploy.dev/static/og-image.png" alt="OpenDeploy — the agent-first deployment platform" /></a>

# OpenDeploy OpenClaw Plugin

OpenClaw plugin for [OpenDeploy](https://opendeploy.dev) — agent-first deployment.

## What's OpenDeploy?

[**OpenDeploy**](https://opendeploy.dev) is the agent-first deployment platform — *help your agent deploy, host, and scale your app*.

One command from any AI coding agent (Claude Code, Codex, Cursor, OpenClaw, …) takes a project from local source → live URL with **no account required for the first deploy**. We support every framework and language: Next.js, Vite, Astro, Nuxt, SvelteKit, Remix, Express, Fastify, Hono, Django, Flask, FastAPI, Rails, Phoenix, Laravel, Spring, .NET, Go, Rust, Bun, Deno, static sites — anything with a build + run.

What the skill does, end-to-end:

1. **Detects the framework** locally (no source upload yet, no telemetry)
2. **Provisions any database** the app needs — postgres / mysql / mongo / redis
3. **Builds and deploys** to `*.opendeploy.run`
4. **Returns a live URL** plus a one-time **claim URL** the user can sign in to later (via SSO) to adopt the project under their account

The split is intentional: **agents deploy, humans observe**. The agent registers an anonymous token and does the work. The human holds the safety escape hatches (delete, revoke token, set budget cap), and watches the deploy in the dashboard.

---

## Install

From ClawHub:

```sh
openclaw plugins install clawhub:opendeploy-dev/opendeploy
openclaw gateway restart
```

From a local checkout:

```sh
git clone --single-branch --depth 1 https://github.com/opendeploy-dev/opendeploy-openclaw-plugin.git
cd opendeploy-openclaw-plugin
openclaw plugins install .
openclaw gateway restart
```

## Usage

Ask OpenClaw in natural language, for example:

```text
Deploy this project with OpenDeploy.
```

OpenClaw loads the skills declared in `openclaw.plugin.json`. The canonical
entrypoint is `opendeploy`; `deploy` is a short alias.

## License

MIT
