#!/usr/bin/env bash
# Inkline for Ubuntu / Linux desktops.
# Adds the printers shared by the office print server (ARIA) as permanent, driverless printers
# (IPP Everywhere through CUPS), so they show in every app's print dialog with full options.
#
#   wget -qO- https://rkparisi.github.io/inkline-releases/inkline-linux.sh | bash
#   bash inkline-linux.sh                 # same, from a downloaded copy
#   bash inkline-linux.sh --server 192.168.40.221
#   bash inkline-linux.sh --remove        # take the Inkline printers off this computer
#
# Needs: CUPS (Ubuntu desktops have it) and sudo rights for adding printers.
set -u

SERVER=""
LABEL="ARIA"
FALLBACKS=("A.local" "192.168.40.221" "192.168.40.69" "192.168.40.249")
MODE="add"

while [ $# -gt 0 ]; do
  case "$1" in
    --server) SERVER="${2:-}"; shift 2 ;;
    --label)  LABEL="${2:-ARIA}"; shift 2 ;;
    --remove) MODE="remove"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 64 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }

echo
echo "  Inkline for Linux"
echo

command -v lpadmin >/dev/null 2>&1 || fail "CUPS is not installed. Run: sudo apt install cups"
command -v lpstat  >/dev/null 2>&1 || fail "CUPS client tools are missing. Run: sudo apt install cups-client"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || fail "Run this as root, or install sudo."
  SUDO="sudo"
  say "Adding printers needs your password once (sudo)."
  $SUDO -v || fail "No permission to add printers."
fi

if [ "$MODE" = "remove" ]; then
  removed=0
  for p in $(lpstat -p 2>/dev/null | awk '{print $2}' | grep -E '_Inkline$'); do
    $SUDO lpadmin -x "$p" && { ok "Removed $p"; removed=$((removed+1)); }
  done
  [ "$removed" -eq 0 ] && say "No Inkline printers on this computer."
  echo; exit 0
fi

# ---- find the print server ------------------------------------------------------------
reachable() { timeout 3 bash -c "exec 3<>/dev/tcp/$1/631" 2>/dev/null; }
if [ -z "$SERVER" ]; then
  for h in "${FALLBACKS[@]}"; do
    if reachable "$h"; then SERVER="$h"; break; fi
  done
fi
[ -n "$SERVER" ] || fail "Can't reach the print server. Is this computer on the office network? (Or pass --server ADDRESS)"
reachable "$SERVER" || fail "Can't reach $SERVER on port 631."
ok "Print server $LABEL found at $SERVER"

# ---- shared queues on it -----------------------------------------------------------------
mapfile -t QUEUES < <(lpstat -h "$SERVER:631" -e 2>/dev/null | sed '/^\s*$/d')
if [ "${#QUEUES[@]}" -eq 0 ]; then
  # older CUPS clients: read the web page instead
  if command -v wget >/dev/null 2>&1; then
    mapfile -t QUEUES < <(wget -qO- "http://$SERVER:631/printers/" | grep -oE 'href="/printers/[^"/?#]+"' | sed -E 's#href="/printers/([^"]+)"#\1#' | sort -u)
  elif command -v curl >/dev/null 2>&1; then
    mapfile -t QUEUES < <(curl -fsS "http://$SERVER:631/printers/" | grep -oE 'href="/printers/[^"/?#]+"' | sed -E 's#href="/printers/([^"]+)"#\1#' | sort -u)
  fi
fi
[ "${#QUEUES[@]}" -gt 0 ] || fail "$LABEL doesn't share any printers right now."

# ---- add them --------------------------------------------------------------------------
ADDED=()
for q in "${QUEUES[@]}"; do
  name="${q}_Inkline"
  pretty="$(echo "$q" | tr '_' ' ') ($LABEL)"
  uri="ipp://$SERVER/printers/$q"
  if lpstat -p "$name" >/dev/null 2>&1; then
    $SUDO lpadmin -p "$name" -v "$uri" >/dev/null 2>&1   # keep the address current
    ok "$pretty is already set up"
    ADDED+=("$name"); continue
  fi
  if $SUDO lpadmin -p "$name" -E -v "$uri" -m everywhere -D "$pretty" -L "via $LABEL" -o printer-is-shared=false 2>/tmp/inkline-lpadmin.err; then
    $SUDO cupsenable "$name" >/dev/null 2>&1; $SUDO cupsaccept "$name" >/dev/null 2>&1
    ok "Added $pretty"
    ADDED+=("$name")
  else
    warn "Could not add $pretty: $(tr '\n' ' ' </tmp/inkline-lpadmin.err)"
  fi
done
[ "${#ADDED[@]}" -gt 0 ] || fail "No printers were added."

# ---- default printer ---------------------------------------------------------------------
echo
current="$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')"
if [ -t 0 ] || [ -e /dev/tty ]; then
  echo "  Which one should be your default printer?"
  i=1; for n in "${ADDED[@]}"; do printf '    %d) %s\n' "$i" "$(echo "${n%_Inkline}" | tr '_' ' ')"; i=$((i+1)); done
  printf '    Enter = keep %s: ' "${current:-none}"
  read -r pick </dev/tty || pick=""
  if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#ADDED[@]}" ]; then
    lpoptions -d "${ADDED[$((pick-1))]}" >/dev/null && ok "Default printer: $(echo "${ADDED[$((pick-1))]%_Inkline}" | tr '_' ' ')"
  fi
fi

echo
ok "Done. The printers are in every app's print dialog (look for \"($LABEL)\")."
say "They print through $LABEL. Run this again any time to refresh, or with --remove to undo."
echo
