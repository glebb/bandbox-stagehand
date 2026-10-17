#!/usr/bin/env bash
# Discover what local-network protocols a Wi-Fi speaker (e.g. JBL Authentics) exposes.
# Pure recon: browses Bonjour/mDNS, resolves services, probes common HTTP ports.
# macOS only tools used (dns-sd, curl) — nothing to install.

set -u

BROWSE_SECONDS=4

# Service types worth checking on a JBL One / Wi-Fi speaker.
SERVICES=(
  _googlecast._tcp     # Chromecast built-in (main control channel)
  _airplay._tcp        # AirPlay 2
  _raop._tcp           # AirPlay audio (Remote Audio Output Protocol)
  _spotify-connect._tcp
  _http._tcp           # generic web/config endpoints
  _googlezone._tcp     # Cast multizone/groups
  _sonos._tcp          # (sanity check; won't be JBL but confirms browsing works)
)

echo "== mDNS / Bonjour browse (${BROWSE_SECONDS}s each) =="
for svc in "${SERVICES[@]}"; do
  echo
  echo "--- $svc ---"
  # dns-sd -B runs forever; capture a short window then kill it.
  out=$(dns-sd -B "$svc" local. 2>/dev/null & pid=$!; sleep "$BROWSE_SECONDS"; kill "$pid" 2>/dev/null)
  # Lines after the header contain "Add" + the instance name.
  echo "$out" | awk '/Add/ {$1=$2=$3=$4=$5=$6=""; sub(/^ +/,""); print "  • " $0}' | sort -u
done

echo
echo "== Resolve the Cast service (name -> host/port/TXT) =="
echo "   Run this and copy the instance name you saw above:"
echo "   dns-sd -L \"<instance name>\" _googlecast._tcp local."
echo
echo "If you give me the speaker's IP, probe its web endpoints:"
echo "   IP=192.168.x.x"
echo "   for p in 80 443 8008 8009 8443 10001 59152; do"
echo "     echo \"port \$p:\"; curl -sk -m 2 \"http://\$IP:\$p/setup/eureka_info\" | head -c 300; echo; done"
