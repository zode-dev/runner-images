#!/usr/bin/env bash
# The acceptance matrix for one image line (REQ-084): at every size the node
# serves, create a sandbox, run commands in it (exec), fork it and check the
# fork, switch the desktop on and take a screenshot. Runs on a node, against
# its zoded (started with --base <the line's golden>, so all sizes come from
# one build).
#
#   scripts/matrix.sh LINE [OUT]
#
# Environment: ZODED_URL (http://127.0.0.1:7070), TOKEN_FILE
# (/etc/zode/zoded.token), SIZES (every size zoded reports), DESKTOP (1;
# 0 skips the desktop, for lines without it), MIN_SHOT_BYTES (25000: a
# screenshot smaller than that is taken as a blank screen). Prints one row per size and
# writes OUT/<line>.tsv and OUT/<line>-<size>.png (OUT: ./matrix).
# Exit status 1 when any check fails.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $0 LINE [OUT]" >&2; exit 2; }
LINE=$1
OUT=${2:-matrix}
API=${ZODED_URL:-http://127.0.0.1:7070}
TOKEN_FILE=${TOKEN_FILE:-/etc/zode/zoded.token}
DESKTOP=${DESKTOP:-1}
mkdir -p "$OUT"

auth=(-H "Authorization: Bearer $(cat "$TOKEN_FILE")")
api() { # METHOD PATH [JSON]
  if [ $# -ge 3 ]; then
    curl -sS --max-time 300 "${auth[@]}" -H 'Content-Type: application/json' -X "$1" "$API$2" -d "$3"
  else
    curl -sS --max-time 300 "${auth[@]}" -X "$1" "$API$2"
  fi
}
# run ID SCRIPT: stdout of `sh -c SCRIPT` in the sandbox; status = its exit code.
run() {
  local r
  r=$(api POST "/v1/sandboxes/$1/exec" "$(jq -nc --arg s "$2" '{argv: ["sh", "-c", $s], timeout_ms: 240000}')")
  printf '%s' "$(jq -r '.stdout // empty' <<<"$r")"
  [ "$(jq -r '.exit_code // 1' <<<"$r")" = 0 ] || { echo "exec failed: $(jq -c '{exit_code, stderr: (.stderr // .error // "")[0:300]}' <<<"$r" 2>/dev/null || echo "$r")" >&2; return 1; }
}

health=$(api GET /healthz)
sizes=${SIZES:-$(jq -r '.sizes[] | .name // .golden' <<<"$health")}
base=$(jq -r '.sizes[0].golden' <<<"$health")
id_line=$(tr -c 'a-z0-9\n' - <<<"$LINE")

# What a sandbox reports: os, vCPUs, MemTotal MB, root GB, kernel. It runs
# in the sandbox, so nothing in it expands here.
# shellcheck disable=SC2016
probe='. /etc/os-release; echo "$ID $VERSION_ID|$(nproc)|$(awk "/MemTotal/{print int(\$2/1024)}" /proc/meminfo)|$(df -BG --output=size / | tail -n1 | tr -dc 0-9)|$(uname -r)"'

status=0
printf 'line\tsize\tready_ms\tos\tvcpus\tmem_mb\troot_gb\tdocker\tfork\tfork_ms\tdesktop\tscreenshot_bytes\n' >"$OUT/$LINE.tsv"
for size in $sizes; do
  row=$(jq -c --arg s "$size" '.sizes[] | select((.name // .golden) == $s)' <<<"$health")
  vcpus=$(jq -r .vcpus <<<"$row")
  ram=$(jq -r .ram_mb <<<"$row")
  disk=$(jq -r .disk_gb <<<"$row")
  id=t73-$id_line-$size
  fid=$id-f
  api DELETE "/v1/sandboxes/$fid" >/dev/null 2>&1
  api DELETE "/v1/sandboxes/$id" >/dev/null 2>&1
  fail=""

  c=$(api POST /v1/sandboxes "$(jq -nc --arg id "$id" --argjson v "$vcpus" --argjson r "$ram" '{id: $id, vcpus: $v, ram_mb: $r}')")
  ready=$(jq -r '.timing.ready_ms // empty' <<<"$c")
  if [ -z "$ready" ]; then
    echo "$LINE $size: create failed: $c" >&2
    printf '%s\t%s\tFAIL\n' "$LINE" "$size" >>"$OUT/$LINE.tsv"
    status=1
    continue
  fi

  # exec: what the guest sees must be the size asked for (94% of RAM: the
  # kernel keeps 2 to 5%, Fedora's small reads 95.0%; 90% of disk, as
  # zoded's grow check), and Docker must run a container.
  p=$(run "$id" "$probe") || fail="$fail exec"
  IFS='|' read -r os g_cpu g_mem g_root kernel <<<"$p"
  [ "${g_cpu:-0}" = "$vcpus" ] || fail="$fail vcpus"
  [ $((${g_mem:-0} * 100)) -ge $((ram * 94)) ] || fail="$fail ram"
  [ $((${g_root:-0} * 10)) -ge $((disk * 9)) ] || fail="$fail disk"
  docker=fail
  if run "$id" 'docker run --rm hello-world 2>&1 | grep -q "Hello from Docker" && echo ok' >/dev/null; then docker=ok; else fail="$fail docker"; fi

  # fork: a RAM fork keeps the parent's files and size and answers exec.
  run "$id" 'echo zode-matrix > /root/matrix-marker && sync' >/dev/null || fail="$fail marker"
  t0=$(date +%s%3N)
  f=$(api POST "/v1/sandboxes/$id/fork" "$(jq -nc --arg id "$fid" '{id: $id}')")
  fork_ms=$(($(date +%s%3N) - t0))
  forkres=fail
  if [ "$(jq -r '.id // empty' <<<"$f")" = "$fid" ]; then
    fp=$(run "$fid" "cat /root/matrix-marker; $probe; getent hosts example.com >/dev/null && echo dns-ok") || true
    if grep -q zode-matrix <<<"$fp" && grep -q "|$vcpus|" <<<"$fp" && grep -q dns-ok <<<"$fp"; then forkres=ok; fi
  else
    echo "$LINE $size: fork: $f" >&2
  fi
  [ "$forkres" = ok ] || fail="$fail fork"
  api DELETE "/v1/sandboxes/$fid" >/dev/null 2>&1

  # desktop: switch it on, take a screenshot (a PNG), switch it off.
  desk=skipped
  shot=0
  if [ "$DESKTOP" = 1 ]; then
    d=$(api PUT "/v1/sandboxes/$id/features" '{"desktop": true}')
    if [ "$(jq -r '.desktop // false' <<<"$d")" = true ]; then
      # Xfce paints a second or two after the switch: a blank 1280x800
      # frame is about 18 KB, the painted Xfce desktop about 34 KB.
      desk=fail
      for _ in $(seq 1 30); do
        curl -sS --max-time 60 "${auth[@]}" -o "$OUT/$LINE-$size.png" "$API/v1/sandboxes/$id/desktop/screenshot"
        shot=$(stat -c %s "$OUT/$LINE-$size.png" 2>/dev/null || echo 0)
        if head -c 8 "$OUT/$LINE-$size.png" | od -An -tx1 | grep -q '89 50 4e 47' && [ "$shot" -gt "${MIN_SHOT_BYTES:-25000}" ]; then
          desk=ok
          break
        fi
        sleep 1
      done
    else
      echo "$LINE $size: desktop: $d" >&2
      desk=fail
    fi
    [ "$desk" = ok ] || fail="$fail desktop"
    api PUT "/v1/sandboxes/$id/features" '{"desktop": false}' >/dev/null
  fi
  api DELETE "/v1/sandboxes/$id" >/dev/null 2>&1

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$LINE" "$size" "$ready" "$os" "$g_cpu" "$g_mem" "$g_root" \
    "$docker" "$forkres" "$fork_ms" "$desk" "$shot" >>"$OUT/$LINE.tsv"
  if [ -n "$fail" ]; then
    echo "$LINE $size (golden ${base}): FAIL:$fail" >&2
    status=1
  fi
  echo "$LINE $size: ready ${ready} ms, $os, $g_cpu vCPU / $g_mem MB / $g_root GB, kernel $kernel, docker $docker, fork $forkres (${fork_ms} ms), desktop $desk"
done
column -t -s "$(printf '\t')" "$OUT/$LINE.tsv"
exit "$status"
