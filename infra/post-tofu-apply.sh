#!/usr/bin/env bash
#
# post-tofu-apply.sh — apply the one UniFi WLAN field that terrifi does
# not expose: `enhanced_iot`.
#
# WHY THIS EXISTS
#   terrifi exposes most of what we need declaratively (create_allow_respond,
#   connection_state_type, connection_states on firewall policies; everything
#   on networks/zones/most WLAN fields). The one stubborn gap is
#   terrifi_wlan.enhanced_iot — a per-WLAN "IoT helper" flag that the UDR-7
#   uses to enable AP-side multicast/proxy-arp behaviors that silently drop
#   routed-in unicast for wireless clients on the SSID. On a stock UniFi
#   controller it defaults to true for IoT-class SSIDs and must be forced
#   to false for off-subnet hosts (Trusted laptop, Apple TV HomeKit hub on
#   Trusted) to reach IoT devices.
#
#   We set `application = "standard"` (not "iot") in wlans.tf to avoid the
#   controller defaulting enhanced_iot back to true on every PUT, but as
#   insurance — in case a future controller upgrade or terrifi behavior
#   change re-introduces the side effect — this script asserts the field
#   explicitly via the UniFi API after every apply.
#
# INVOKED BY
#   `terraform_data.post_apply_fixups` in post_apply.tf via local-exec.
#   Inherits UNIFI_API + UNIFI_API_KEY from the `op run` environment.
#
# WHEN TO REMOVE THIS FILE
#   When terrifi exposes `enhanced_iot` on terrifi_wlan, set it in wlans.tf
#   and delete this script + post_apply.tf.

if [[ -z "$UNIFI_API" || -z "$UNIFI_API_KEY" ]]; then
  echo "ERROR: UNIFI_API and UNIFI_API_KEY must be set." >&2
  echo "Run tofu via: op run --env-file=infra/op-env.template -- tofu apply" >&2
  exit 1
fi

BASE="$UNIFI_API"
HDR="X-API-Key: $UNIFI_API_KEY"
SITE="default"
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

curl -sk -H "$HDR" "$BASE/proxy/network/api/s/$SITE/rest/wlanconf" > "$WORK/wlans.json"
WLAN_IOT_ID=$(python3 -c "
import json, sys
for w in json.load(open('$WORK/wlans.json'))['data']:
    if w.get('name') == 'Home-IoT':
        print(w['_id']); sys.exit(0)
sys.exit(1)
")
if [[ -z "$WLAN_IOT_ID" ]]; then
  echo "ERROR: could not find Home-IoT WLAN. Has terraform applied?" >&2
  exit 1
fi

echo "=== enhanced_iot=false on Home-IoT WLAN ($WLAN_IOT_ID) ==="
curl -sk -H "$HDR" "$BASE/proxy/network/api/s/$SITE/rest/wlanconf/$WLAN_IOT_ID" > "$WORK/wlan.json"
python3 -c "
import json
d = json.load(open('$WORK/wlan.json'))
w = d['data'][0]
w['enhanced_iot'] = False
print(json.dumps(w))
" > "$WORK/wlan_patched.json"
code=$(curl -sk -o "$WORK/resp.json" -w "%{http_code}" -X PUT \
  -H "$HDR" -H "Content-Type: application/json" \
  --data @"$WORK/wlan_patched.json" \
  "$BASE/proxy/network/api/s/$SITE/rest/wlanconf/$WLAN_IOT_ID")
echo "  PUT HTTP $code"
[[ "$code" != "200" ]] && { cat "$WORK/resp.json"; exit 1; }

echo "=== Done. ==="
