#!/usr/bin/env bash
# Auto-approve only read-only OpenDeploy checks. Mutations, consent-bearing
# commands, shell composition, and update/install actions fall through to the
# normal permission prompt.

set -e

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

allow() {
  local reason="$1"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "$reason"
  }
}
EOF
  exit 0
}

deny() {
  local reason="$1"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
  exit 0
}

# OpenDeploy deploy/auth workflows must use the checked global binary. A pinned
# or latest npx invocation bypasses the global npm update gate and reintroduces
# "checked one binary, executed another" behavior.
if [[ "$command" =~ (^|[[:space:];\|\&])npx[[:space:]]+(-y[[:space:]]+)?@opendeploydev/cli(@[A-Za-z0-9._-]+)?($|[[:space:];\|\&]) ]]; then
  deny "Use global opendeploy after npm install -g @opendeploydev/cli@latest; npx @opendeploydev/cli is not an OpenDeploy fallback runner"
fi

# Reject shell composition for auto-approval. A command can still run through the
# normal permission flow; it just does not get this plugin's allow decision.
if [[ "$command" == *$'\n'* ||
      "$command" == *";"* ||
      "$command" == *"|"* ||
      "$command" == *"&"* ||
      "$command" == *">"* ||
      "$command" == *"<"* ||
      "$command" == *"\`"* ||
      "$command" == *'$('* ]]; then
  exit 0
fi

extract_cli_args() {
  local cmd="$1"

  if [[ "$cmd" =~ ^opendeploy($|[[:space:]]+)(.*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

cli_args="$(extract_cli_args "$command" || true)"

if [[ -n "$cli_args" ]]; then
  # Never auto-approve commands that can mutate, reveal secrets, or bypass a
  # documented consent gate.
  case "$cli_args" in
    *"--confirm-"*|*"--show-secrets"*|\
    auth\ guest*|auth\ login*|auth\ logout*|auth\ revoke*|\
    projects\ create*|projects\ delete*|\
    dependencies\ create*|dependencies\ delete*|\
    services\ create*|services\ delete*|services\ restart*|services\ start*|services\ stop*|services\ resize*|\
    services\ env\ set*|services\ env\ patch*|services\ env\ unset*|services\ env\ reconcile*|\
    services\ config\ patch*|\
    upload\ update-source*|\
    deployments\ create*|deployments\ cancel*|deployments\ rollback*|deployments\ retry*|\
    domains\ create*|domains\ delete*|domains\ update-subdomain*|\
    monitoring\ alarms\ create*|monitoring\ alarms\ update*|monitoring\ alarms\ delete*|monitoring\ alarms\ note\ *|\
    monitoring\ alarms\ acknowledge*|monitoring\ alarms\ resolve*|monitoring\ alarms\ suppress*|monitoring\ alarms\ silence*|\
    monitoring\ alarms\ engage-support*|monitoring\ alarms\ support-checkin*|\
    monitoring\ alert-rules\ create*|monitoring\ alert-rules\ update*|monitoring\ alert-rules\ delete*|\
    deploy\ step*|deploy\ apply*)
      exit 0
      ;;
  esac

  case "$cli_args" in
    ""|--version|version|version\ --json|status\ --json|doctor\ --json|routes\ list\ --json|update\ check\ --json|auth\ status\ --json|context\ resolve\ --json|regions\ list\ --json)
      allow "OpenDeploy read-only CLI check auto-approved"
      ;;
    preflight\ *--json|analyze\ *--json|env\ scan\ *--json|archive\ create\ *--json|deploy\ plan\ *--json|deploy\ verify\ *--json|deploy\ wait\ *--json|deploy\ progress\ *--json|deploy\ report\ *--json)
      allow "OpenDeploy read-only deploy planning/check auto-approved"
      ;;
    projects\ list\ *--json|projects\ get\ *--json|services\ list\ *--json|services\ get\ *--json|services\ status\ *--json|services\ health\ *--json|services\ config\ get\ *--json|dependencies\ status\ *--json|deployments\ get\ *--json|deployments\ list\ *--json|domains\ list\ *--json|domains\ check-subdomain\ *--json|monitoring\ project-health\ *--json|monitoring\ project-metrics\ *--json|monitoring\ dependency-health\ *--json|monitoring\ dependency-metrics\ *--json|monitoring\ quota\ *--json|monitoring\ alarms\ --json|monitoring\ alarms\ list\ *--json|monitoring\ alarms\ get\ *--json|monitoring\ alarms\ notes\ *--json|monitoring\ alarms\ history\ *--json|monitoring\ alarms\ project*--json|monitoring\ alarms\ service*--json|logs\ *--json)
      allow "OpenDeploy read-only resource inspection auto-approved"
      ;;
  esac
fi

# `npm view @opendeploydev/cli ...` (read-only metadata)
if [[ "$command" =~ ^npm[[:space:]]view[[:space:]]@opendeploydev/cli ]]; then
  allow "OpenDeploy package metadata read auto-approved"
fi

# `npm list -g @opendeploydev/cli --depth=0 --json` (read-only global package metadata)
if [[ "$command" =~ ^npm[[:space:]]list[[:space:]]-g[[:space:]]@opendeploydev/cli([[:space:]]|$) ]]; then
  allow "OpenDeploy global package metadata read auto-approved"
fi

# `claude plugin list ...` is read-only. Install/update/remove should prompt.
if [[ "$command" =~ ^claude[[:space:]]plugin[[:space:]]list([[:space:]]|$) ]]; then
  allow "Claude plugin list auto-approved"
fi

# Pass through — let the standard permission flow handle it.
exit 0
