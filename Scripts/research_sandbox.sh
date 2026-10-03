#!/usr/bin/env bash
# Builds and runs the web research sandbox with Apple `container`.
#
#   Scripts/research_sandbox.sh build    build the tuff-web-research image
#   Scripts/research_sandbox.sh start    start a fresh sandbox on 127.0.0.1:9000 (TUFF_RESEARCH_SANDBOX_PORT)
#   Scripts/research_sandbox.sh start --proxy socks5://HOST:PORT
#                                        the same, with every connection sent
#                                        through a SOCKS5 or HTTP proxy
#   Scripts/research_sandbox.sh stop     stop and remove the sandbox
#   Scripts/research_sandbox.sh status   report whether the sandbox answers
#   Scripts/research_sandbox.sh selftest check that the sandbox refuses the Mac,
#                                        the local network and metadata addresses
#
# The sandbox is the only part of `tuff research` with internet access. It runs
# in its own Linux VM with a read-only root and no Mac folders mounted. A
# firewall inside the VM lets it reach public internet addresses, plus DNS on
# the Mac when the Mac is its name server, and the
# server runs as a non-root user with no Linux capabilities. Its port is
# published to the Mac's loopback address only. With --proxy (or
# TUFF_RESEARCH_PROXY), the firewall allows the proxy and nothing else. The
# proxy login, if it needs one, comes from the Keychain item
# "tuff-research-proxy" or TUFF_RESEARCH_PROXY_USER and
# TUFF_RESEARCH_PROXY_PASSWORD, never from the command line.
# See docs/WEB_RESEARCH.md.

set -euo pipefail

image="tuff-web-research:latest"
name="tuff-web-research"
port="${TUFF_RESEARCH_SANDBOX_PORT:-9000}"
# DNS servers for the VM, space-separated. Unset, the VM asks the Mac, which
# uses the same DNS as the rest of the Mac; set it (for example to
# "1.1.1.1 9.9.9.9") to use public resolvers instead.
dns_servers="${TUFF_RESEARCH_DNS:-}"
proxy="${TUFF_RESEARCH_PROXY:-}"
keychain_service="tuff-research-proxy"
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
context="$script_directory/../Sandbox/web-research"

require_container() {
  if ! command -v container >/dev/null 2>&1; then
    echo "Apple container is not installed; see https://github.com/apple/container" >&2
    exit 1
  fi
  container system status >/dev/null 2>&1 || container system start
}

health() {
  curl -fsS --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1
}

# Checks the --proxy value: socks5:// or http://, a host and a port, no login.
check_proxy() {
  python3 - "$1" <<'PY'
import sys, urllib.parse
parts = urllib.parse.urlsplit(sys.argv[1])
try:
    port = parts.port
except ValueError:
    port = None
if parts.username or parts.password:
    sys.exit("put the proxy login in the Keychain, not in the URL; see docs/WEB_RESEARCH.md")
if parts.scheme not in ("socks5", "http") or not parts.hostname or not port \
        or parts.path not in ("", "/") or parts.query or parts.fragment:
    sys.exit("--proxy must look like socks5://HOST:PORT or http://HOST:PORT")
PY
}

# Exports the proxy login from the environment or the Keychain, if there is
# one. It reaches the VM through `--env NAME`, which copies the value from
# this script's environment, so it never appears in a command line.
load_proxy_login() {
  if [[ -n "${TUFF_RESEARCH_PROXY_USER:-}" ]]; then
    export TUFF_RESEARCH_PROXY_USER TUFF_RESEARCH_PROXY_PASSWORD="${TUFF_RESEARCH_PROXY_PASSWORD:-}"
    return 0
  fi
  command -v security >/dev/null 2>&1 || return 0
  local account
  account="$(security find-generic-password -s "$keychain_service" 2>/dev/null \
    | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p')" || true
  [[ -n "$account" ]] || return 0
  TUFF_RESEARCH_PROXY_USER="$account"
  TUFF_RESEARCH_PROXY_PASSWORD="$(security find-generic-password -s "$keychain_service" -w)" \
    || { echo "could not read the proxy login from the Keychain" >&2; exit 1; }
  export TUFF_RESEARCH_PROXY_USER TUFF_RESEARCH_PROXY_PASSWORD
}

case "${1:-}" in
  build)
    require_container
    container build -t "$image" "$context"
    ;;
  start)
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --proxy) [[ $# -ge 2 ]] || { echo "--proxy needs a URL" >&2; exit 2; }; proxy="$2"; shift 2 ;;
        --proxy=*) proxy="${1#--proxy=}"; shift ;;
        *) echo "unknown option for start: $1" >&2; exit 2 ;;
      esac
    done
    if [[ -n "$proxy" ]]; then
      check_proxy "$proxy" || exit 2
      load_proxy_login
    fi
    require_container
    container stop "$name" >/dev/null 2>&1 || true
    container delete "$name" >/dev/null 2>&1 || true
    # The entrypoint starts as root with these four capabilities only, to load
    # the firewall; the server then gives them all up and runs as user 10001.
    run_options=(
      --detach --rm --name "$name"
      --read-only --tmpfs /tmp
      --cap-drop ALL --cap-add NET_ADMIN --cap-add SETUID --cap-add SETGID --cap-add SETPCAP
      --ulimit nproc=512
      --cpus 2 --memory 1G
      --publish "127.0.0.1:$port:9000"
    )
    for server in $dns_servers; do
      run_options+=(--dns "$server")
    done
    if [[ -n "${SEARXNG_URL:-}" ]]; then
      run_options+=(--env "SEARXNG_URL=$SEARXNG_URL")
    fi
    if [[ -n "$proxy" ]]; then
      run_options+=(--env "TUFF_RESEARCH_PROXY=$proxy")
      if [[ -n "${TUFF_RESEARCH_PROXY_USER:-}" ]]; then
        run_options+=(--env TUFF_RESEARCH_PROXY_USER --env TUFF_RESEARCH_PROXY_PASSWORD)
      fi
      if [[ -n "${TUFF_RESEARCH_DOH:-}" ]]; then
        run_options+=(--env "TUFF_RESEARCH_DOH=$TUFF_RESEARCH_DOH")
      fi
    fi
    container run "${run_options[@]}" "$image" >/dev/null
    for _ in $(seq 1 50); do
      if health; then
        if [[ -n "$proxy" ]]; then
          echo "web research sandbox ready at http://127.0.0.1:$port, sending everything through the proxy"
        else
          echo "web research sandbox ready at http://127.0.0.1:$port"
        fi
        exit 0
      fi
      sleep 0.2
    done
    echo "sandbox started but did not answer on 127.0.0.1:$port; see: container logs $name" >&2
    exit 1
    ;;
  stop)
    require_container
    container stop "$name" >/dev/null 2>&1 || true
    container delete "$name" >/dev/null 2>&1 || true
    echo "web research sandbox stopped"
    ;;
  status)
    if health; then
      echo "web research sandbox is answering at http://127.0.0.1:$port"
    else
      echo "web research sandbox is not answering at http://127.0.0.1:$port" >&2
      exit 1
    fi
    ;;
  selftest)
    require_container
    health || { echo "start the sandbox first: $0 start" >&2; exit 1; }
    failures=0
    pass() { echo "  ok    $1"; }
    fail() { echo "  FAIL  $1" >&2; failures=$((failures + 1)); }
    note() { echo "  note  $1"; }
    proxy_kind="$(curl -fsS --max-time 2 "http://127.0.0.1:$port/health" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("proxy") or "")' 2>/dev/null || true)"
    proxy_address="" proxy_port=""
    if [[ -n "$proxy_kind" ]]; then
      read -r proxy_address proxy_port < <(container exec "$name" cat /tmp/tuff-proxy-endpoint 2>/dev/null) || true
      if [[ -z "$proxy_port" ]]; then
        fail "the sandbox says it uses a proxy, but the firewall has no proxy rule"
      fi
    fi

    echo "Fetches the sandbox must refuse:"
    gateway="$(container exec "$name" python3 -c '
import socket, struct
for line in open("/proc/net/route").read().splitlines()[1:]:
    fields = line.split()
    if fields[1] == "00000000":
        print(socket.inet_ntoa(struct.pack("<L", int(fields[2], 16))))
        break
')"
    blocked_urls=(
      "http://$gateway/"
      "http://$gateway:8080/v1/models"
      "http://127.0.0.1:8080/v1/models"
      "http://localhost/"
      "http://[::1]/"
      "http://10.0.0.1/"
      "http://172.16.0.1/"
      "http://192.168.1.1/"
      "http://169.254.169.254/latest/meta-data/"
      "http://100.100.100.200/"
      "http://0.0.0.0/"
      "http://localtest.me/"
      "http://example.com:8080/"
      "file:///etc/passwd"
      "ftp://example.com/"
    )
    for url in "${blocked_urls[@]}"; do
      reply="$(curl -sS --max-time 20 -H 'Content-Type: application/json' \
        --data "{\"url\": \"$url\"}" "http://127.0.0.1:$port/v1/fetch")"
      code="$(printf '%s' "$reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("error",{}).get("code",""))' 2>/dev/null || true)"
      case "$code" in
        blocked_address|blocked_port|invalid_url|dns_error) pass "$url refused ($code)" ;;
        *) fail "$url was not refused: ${reply:0:200}" ;;
      esac
    done

    echo "The VM's own protection:"
    if container exec "$name" nft list table inet tuff_sandbox >/dev/null 2>&1; then
      pass "the firewall is loaded"
    else
      fail "the firewall is not loaded"
    fi
    privileges="$(container exec "$name" python3 -c '
import glob
for path in glob.glob("/proc/[0-9]*/cmdline"):
    try:
        if b"/app/server.py" not in open(path, "rb").read().split(b"\0"):
            continue
        status = dict(l.split(":", 1) for l in open(path[:-7] + "status") if ":" in l)
    except OSError:
        continue
    caps = [n for n in ("CapPrm", "CapEff", "CapBnd", "CapAmb") if int(status[n], 16)]
    print(status["Uid"].split()[0], ",".join(caps) or "none")
    break
' 2>/dev/null || true)"
    if [[ "$privileges" == "10001 none" ]]; then
      pass "the server runs as user 10001 with no capabilities"
    else
      fail "the server's user and capabilities are not as expected: ${privileges:-not found}"
    fi

    # These run as the server's user, as code that took the server over would.
    echo "Direct connections from inside the VM, which must fail:"
    # The Mac's DNS port (53) is the one exception, when the VM uses it.
    for target in "$gateway:8080" "$gateway:22" "$gateway:5000" "$gateway:443" \
                  "192.168.1.1:80" "192.168.0.1:80" "10.0.0.1:80" "169.254.169.254:80"; do
      if container exec --user 10001:10001 "$name" python3 -c "
import socket, sys
host, port = sys.argv[1].rsplit(':', 1)
try:
    socket.create_connection((host, int(port)), timeout=3).close()
except OSError:
    sys.exit(1)
" "$target" >/dev/null 2>&1; then
        fail "the VM can open a connection to $target"
      else
        pass "the VM cannot connect to $target"
      fi
    done

    # Every TCP port on the Mac. DNS (53) may answer when the VM's name server
    # is the Mac, which is the default; nothing else may.
    echo "Every TCP port on the Mac, from inside the VM:"
    open_ports="$(container exec --user 10001:10001 "$name" python3 -c '
import socket, sys
from concurrent.futures import ThreadPoolExecutor
host = sys.argv[1]
def probe(port):
    try:
        socket.create_connection((host, port), timeout=1).close()
        return port
    except OSError:
        return None
with ThreadPoolExecutor(64) as pool:
    print(" ".join(str(p) for p in pool.map(probe, range(1, 65536)) if p))
' "$gateway" 2>/dev/null)" || open_ports="error"
    mac_dns="no"
    if container exec "$name" awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf 2>/dev/null \
        | grep -qx "$gateway"; then
      mac_dns="yes"
    fi
    [[ -z "$proxy_kind" ]] || mac_dns="no"  # No DNS exception with the proxy on.
    if [[ -n "$proxy_kind" && "$proxy_address" == "$gateway" ]]; then
      # A proxy running on the Mac is the one port the VM may reach there.
      if [[ "$open_ports" == "$proxy_port" ]]; then
        open_ports=""
        pass "only the proxy's port ($proxy_port) on the Mac is reachable"
      elif [[ -z "$open_ports" ]]; then
        fail "the proxy's port ($proxy_port) on the Mac is not reachable; is the proxy running?"
        open_ports="checked"
      fi
    fi
    case "$open_ports" in
      checked) ;;
      "")
        [[ -n "$proxy_kind" && "$proxy_address" == "$gateway" ]] || pass "no port on the Mac is reachable" ;;
      53)
        if [[ "$mac_dns" == "yes" ]]; then
          pass "only the Mac's DNS port (53) is reachable, as configured"
        else
          fail "the Mac's port 53 is reachable although the VM does not use the Mac for DNS"
        fi ;;
      error)
        fail "the port scan of the Mac did not run" ;;
      *)
        fail "the VM can reach these ports on the Mac: $open_ports" ;;
    esac

    if [[ -n "$proxy_kind" ]]; then
      echo "The proxy ($proxy_kind) is the only way out:"
      # Public addresses the VM could reach without the proxy; the proxy's
      # own address is skipped, since that one must answer.
      for target in "1.1.1.1:443" "9.9.9.9:443" "8.8.8.8:53"; do
        [[ "${target%:*}" == "$proxy_address" ]] && continue
        if container exec --user 10001:10001 "$name" python3 -c "
import socket, sys
host, port = sys.argv[1].rsplit(':', 1)
try:
    socket.create_connection((host, int(port)), timeout=3).close()
except OSError:
    sys.exit(1)
" "$target" >/dev/null 2>&1; then
          fail "the VM can reach $target without the proxy"
        else
          pass "the VM cannot reach $target without the proxy"
        fi
      done
      if container exec --user 10001:10001 "$name" python3 -c "
import socket
socket.setdefaulttimeout(5)
socket.getaddrinfo('example.com', 443)
" >/dev/null 2>&1; then
        fail "the VM can look up names outside the proxy (DNS leak)"
      else
        pass "the VM cannot look up names outside the proxy"
      fi
      # The address websites see. Compared with the Mac's own, from a public
      # echo service; a match is only a note, since a VPN on the Mac can carry
      # the proxy and leave from the same address.
      vm_ip="$(curl -sS --max-time 40 -H 'Content-Type: application/json' \
        --data '{"url":"https://api.ipify.org/"}' "http://127.0.0.1:$port/v1/fetch" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("text","").strip())' 2>/dev/null || true)"
      mac_ip="$(curl -fsS --max-time 10 https://api.ipify.org/ 2>/dev/null || true)"
      if [[ -z "$vm_ip" ]]; then
        fail "could not fetch https://api.ipify.org/ through the proxy"
      elif [[ -z "$mac_ip" ]]; then
        note "websites see $vm_ip; the Mac's own address could not be checked"
      elif [[ "$vm_ip" != "$mac_ip" ]]; then
        pass "websites see the proxy's address $vm_ip, not the Mac's $mac_ip"
      else
        note "websites see $vm_ip, the same address as the Mac; expected only if a VPN on the Mac carries the proxy"
      fi
    fi

    echo "Requests to the sandbox API that must be refused:"
    status="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: attacker.example' \
      -H 'Content-Type: application/json' --data '{"url":"https://example.com/"}' \
      "http://127.0.0.1:$port/v1/fetch")"
    [[ "$status" == "403" ]] && pass "foreign Host header refused" || fail "foreign Host header answered $status"
    status="$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: text/plain' \
      --data '{"url":"https://example.com/"}' "http://127.0.0.1:$port/v1/fetch")"
    [[ "$status" == "415" ]] && pass "browser-style simple POST refused" || fail "simple POST answered $status"

    echo "A public page must still work:"
    if curl -fsS --max-time 30 -H 'Content-Type: application/json' \
        --data '{"url":"https://example.com/"}' "http://127.0.0.1:$port/v1/fetch" | grep -q '"text"'; then
      pass "https://example.com/ fetched"
    else
      fail "https://example.com/ could not be fetched; check the VM's internet access"
    fi

    if [[ "$failures" -gt 0 ]]; then
      echo "$failures check(s) failed" >&2
      exit 1
    fi
    echo "all sandbox checks passed"
    ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
