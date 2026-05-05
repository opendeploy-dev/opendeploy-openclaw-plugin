# Operation logger for the opendeploy skill. This file is installed to
# ~/.opendeploy/lib/log.sh by references/auth.md and sourced by the other
# reference flows. JSONL, daily-rolled, secret-redacted. Logging failures are
# swallowed so logging never aborts a deploy.
#
# Auditable copy: this is the canonical, version-controlled source of the
# `od_log` function. references/auth.md prefers this file (via cp) over its
# embedded heredoc fallback so scanners and users can review the exact logger
# code that ends up at ~/.opendeploy/lib/log.sh.

OD_LOG_DIR="${OD_LOG_DIR:-$HOME/.opendeploy/logs}"
OD_LOG_FILE="$OD_LOG_DIR/$(date -u +%Y-%m-%d).log"
[ -d "$OD_LOG_DIR" ] || { mkdir -p "$OD_LOG_DIR" && chmod 700 "$OD_LOG_DIR"; }
[ -e "$OD_LOG_FILE" ] || { : > "$OD_LOG_FILE" 2>/dev/null && chmod 600 "$OD_LOG_FILE"; }

# Usage: od_log <level> <step> [key value]...
#   level: info | warn | error
#   step:  dot-separated identifier, e.g. deploy.upload_only
#
# Sensitive keys (api_key, bind_sig, password, token, *secret*, *Authorization*)
# are dropped before serialisation so an accidental leak from a caller never
# reaches disk.
od_log() {
  local level=${1:-info} step=${2:-unknown}; shift 2 2>/dev/null || true
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local args=(--arg ts "$ts" --arg lv "$level" --arg st "$step")
  local merge='{ts:$ts, level:$lv, step:$st}'
  local i=0
  while [ $# -ge 2 ]; do
    case "$1" in
      api_key|bind_sig|password|token|*secret*|*Authorization*|authorization)
        shift 2; continue ;;
    esac
    args+=(--arg "k$i" "$1" --arg "v$i" "$2")
    merge="$merge + {(\$k$i): \$v$i}"
    i=$((i+1))
    shift 2
  done
  jq -nc "${args[@]}" "$merge" >> "$OD_LOG_FILE" 2>/dev/null || true
}
