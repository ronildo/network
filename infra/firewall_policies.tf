# Firewall policies
#
# Design (balanced posture):
#
#   Trusted        →  any zone        ALLOW   (you administer everything)
#   IoT            →  Trusted         BLOCK   (IoT cannot pivot to laptops)
#   IoT            →  Guest           BLOCK
#   IoT            →  IoT-Quarantine  BLOCK
#   IoT-Quarantine →  Internet (WAN)  BLOCK   (cameras don't phone home)
#   IoT-Quarantine →  any LAN zone    BLOCK
#   Guest          →  any LAN zone    BLOCK   (visitors get internet only)
#
# GOTCHA: UniFi's zone-based firewall ships a built-in BLOCK default for
# Trusted → IoT, Trusted → Guest, and Trusted → IoT-Quarantine. The global
# "Default Security Posture: Allow All" toggle (Settings → Networks) does
# NOT override these per-zone-pair defaults — it only applies to brand-new
# zone pairs created after the toggle is set. So the "Trusted → any zone
# ALLOW" line above is achieved by writing EXPLICIT ALLOW policies below,
# not by relying on a default. Without them, your laptop cannot reach the
# thermostat, the printer, or the camera admin page even though stateful
# return traffic for outbound flows still works.
#
# GOTCHA #2 (stateful return path): Two firewall-policy fields are
# load-bearing for cross-VLAN traffic to actually work, and neither is
# set by terrifi's defaults:
#
#   - ALLOW Trusted→* rules need `create_allow_respond = true` so the
#     rule installs a stateful conntrack entry. Without it, the forward
#     Trusted→IoT packet is allowed but the return packet isn't
#     recognized as "established" and gets caught by our IoT→Trusted
#     Block (below).
#
#   - BLOCK *→Trusted rules need
#         connection_state_type = "CUSTOM"
#         connection_states     = ["NEW"]
#     so they only block newly-initiated connections, letting established
#     return traffic for Trusted-initiated flows fall through to the
#     predefined "Allow Return Traffic" rule. Our custom Block sits at
#     index 10000 and the predef Allow Return Traffic at 30000 (lower
#     index = higher priority), so without this scoping our Block wins
#     and the return path dies.
#
# Both are set declaratively on the rules below — terrifi exposes both
# fields, you just have to set them explicitly because the defaults are
# wrong for this posture.
#
# Symptom if these get reverted: HomeKit "No Response" after the app idles
# long enough, intermittent loss of admin access to IoT devices, ping
# from Trusted to IoT clients silently times out while ping to 10.20.0.1
# (the gateway iface) still works.
#
# RELATED: there is also a per-WLAN `enhanced_iot` flag with the same
# class of effect that terrifi does NOT expose. It is forced to false via
# `post-tofu-apply.sh` (invoked by terraform_data.post_apply_fixups in
# post_apply.tf). See that file for details.
#
# Multicast/mDNS from Trusted into IoT (so Sonos/Chromecast/HomeKit
# discovery still works) is handled separately by enabling Gateway mDNS
# Proxy in the UI — see UI-CHECKLIST.md step 8.

# ---- IoT cannot reach Trusted ---------------------------------------------
# connection_state_type = "CUSTOM" + connection_states = ["NEW"] is what
# makes this rule only block newly-initiated IoT→Trusted connections,
# letting established return traffic for Trusted-initiated flows fall
# through to the predefined "Allow Return Traffic" rule at idx 30000.
# Without this, our Block here (at idx 10000) intercepts the return.
# Same pattern on the Quarantine→Trusted and Guest→Trusted blocks below.
resource "terrifi_firewall_policy" "block_iot_to_trusted" {
  name        = "Block IoT to Trusted"
  description = "Compromised IoT device must not reach personal devices."
  action      = "BLOCK"

  connection_state_type = "CUSTOM"
  connection_states     = ["NEW"]

  source {
    zone_id = terrifi_firewall_zone.iot.id
  }
  destination {
    zone_id = terrifi_firewall_zone.trusted.id
  }
}

# ---- IoT cannot reach Guest ----------------------------------------------
resource "terrifi_firewall_policy" "block_iot_to_guest" {
  name   = "Block IoT to Guest"
  action = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.iot.id
  }
  destination {
    zone_id = terrifi_firewall_zone.guest.id
  }
}

# ---- IoT cannot reach Quarantine -----------------------------------------
resource "terrifi_firewall_policy" "block_iot_to_quarantine" {
  name   = "Block IoT to IoT-Quarantine"
  action = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.iot.id
  }
  destination {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
}

# ---- Quarantine has no internet egress ------------------------------------
# This rule references the built-in "External" zone, which is the WAN.
# We can't create that zone in Terraform, so look up its ID in the UI
# (Settings > Security > Firewall > Zones) and paste it into terraform.tfvars
# as `external_zone_id` if you want this rule.
#
# Until you set it, the rule below is a no-op (count = 0).
variable "external_zone_id" {
  description = "ID of the built-in External (WAN) zone. Look it up in the UI."
  type        = string
  default     = ""
}

resource "terrifi_firewall_policy" "block_quarantine_to_internet" {
  count = (var.block_quarantine_internet && var.external_zone_id != "") ? 1 : 0

  name        = "Block Quarantine to Internet"
  description = "No-name cameras: no phone-home, no exfiltration."
  action      = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
  destination {
    zone_id = var.external_zone_id
  }
}

# ---- Quarantine cannot reach any LAN zone --------------------------------
resource "terrifi_firewall_policy" "block_quarantine_to_trusted" {
  name   = "Block Quarantine to Trusted"
  action = "BLOCK"

  connection_state_type = "CUSTOM"
  connection_states     = ["NEW"]

  source {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
  destination {
    zone_id = terrifi_firewall_zone.trusted.id
  }
}

resource "terrifi_firewall_policy" "block_quarantine_to_iot" {
  name   = "Block Quarantine to IoT"
  action = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
  destination {
    zone_id = terrifi_firewall_zone.iot.id
  }
}

resource "terrifi_firewall_policy" "block_quarantine_to_guest" {
  name   = "Block Quarantine to Guest"
  action = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
  destination {
    zone_id = terrifi_firewall_zone.guest.id
  }
}

# ---- Guest cannot reach any LAN zone -------------------------------------
resource "terrifi_firewall_policy" "block_guest_to_trusted" {
  name   = "Block Guest to Trusted"
  action = "BLOCK"

  connection_state_type = "CUSTOM"
  connection_states     = ["NEW"]

  source {
    zone_id = terrifi_firewall_zone.guest.id
  }
  destination {
    zone_id = terrifi_firewall_zone.trusted.id
  }
}

resource "terrifi_firewall_policy" "block_guest_to_iot" {
  name   = "Block Guest to IoT"
  action = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.guest.id
  }
  destination {
    zone_id = terrifi_firewall_zone.iot.id
  }
}

resource "terrifi_firewall_policy" "block_guest_to_quarantine" {
  name   = "Block Guest to IoT-Quarantine"
  action = "BLOCK"

  source {
    zone_id = terrifi_firewall_zone.guest.id
  }
  destination {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
}

# ---- Trusted → lower-trust zones: explicit ALLOWs -------------------------
# The asymmetry of the posture (Trusted can reach down, lower trust cannot
# reach up) requires EXPLICIT ALLOW policies because UniFi's zone-based
# firewall ships a built-in BLOCK default for each of these pairs. See the
# GOTCHA note at the top of this file.
#
# Stateful firewall still lets reply packets back, so unsolicited connections
# from the lower-trust zone don't happen — the IoT → Trusted BLOCK above is
# what enforces that. If you ever want to lock these ALLOWs down further,
# narrow them to specific ports/IPs (that's the "hardened" posture, not
# balanced).

resource "terrifi_firewall_policy" "allow_trusted_to_iot" {
  name        = "Allow Trusted to IoT"
  description = "Laptop/phone can reach smart plugs, HomeKit accessories, Sonos, Chromecast."
  action      = "ALLOW"

  # create_allow_respond=true installs a stateful conntrack entry for this
  # rule. Without it, the forward Trusted→IoT request is allowed but the
  # return traffic isn't recognized as "established" — it then matches
  # the IoT→Trusted Block (above) and gets dropped. Symptom: HomeKit
  # "No Response" after the app idles long enough for the conntrack
  # entry to be needed. Same pattern on the two Allow rules below.
  create_allow_respond = true

  source {
    zone_id = terrifi_firewall_zone.trusted.id
  }
  destination {
    zone_id = terrifi_firewall_zone.iot.id
  }
}

resource "terrifi_firewall_policy" "allow_trusted_to_iot_quarantine" {
  name        = "Allow Trusted to IoT-Quarantine"
  description = "Laptop can reach the camera admin UI to configure quarantined devices."
  action      = "ALLOW"

  create_allow_respond = true

  source {
    zone_id = terrifi_firewall_zone.trusted.id
  }
  destination {
    zone_id = terrifi_firewall_zone.iot_quarantine.id
  }
}

resource "terrifi_firewall_policy" "allow_trusted_to_guest" {
  name        = "Allow Trusted to Guest"
  description = "Admin can reach a guest device if needed (rare — included for symmetry)."
  action      = "ALLOW"

  create_allow_respond = true

  source {
    zone_id = terrifi_firewall_zone.trusted.id
  }
  destination {
    zone_id = terrifi_firewall_zone.guest.id
  }
}

# ---- Work zone: total bidirectional isolation -----------------------------
# Work is different from the other zones: nothing on the home side should
# see the work MacBook, and the work MacBook shouldn't see anything on the
# home side either. So BOTH directions are blocked for every pair involving
# Work. Internet egress (Work → External/WAN) stays allowed by default.
#
# This protects in two directions at once:
#   - Compromise/MDM-snooping on the work device can't reach your home
#     devices, NAS, Home Assistant, or laptops.
#   - Your home traffic (Tailscale clients included — they appear as
#     Trusted-zone origin) can't accidentally route into the work device.

resource "terrifi_firewall_policy" "block_work_to_trusted" {
  name        = "Block Work to Trusted"
  description = "Work MacBook cannot see personal devices, NAS, or Home Assistant."
  action      = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.work.id }
  destination { zone_id = terrifi_firewall_zone.trusted.id }
}

resource "terrifi_firewall_policy" "block_work_to_iot" {
  name   = "Block Work to IoT"
  action = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.work.id }
  destination { zone_id = terrifi_firewall_zone.iot.id }
}

resource "terrifi_firewall_policy" "block_work_to_iot_quarantine" {
  name   = "Block Work to IoT-Quarantine"
  action = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.work.id }
  destination { zone_id = terrifi_firewall_zone.iot_quarantine.id }
}

resource "terrifi_firewall_policy" "block_work_to_guest" {
  name   = "Block Work to Guest"
  action = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.work.id }
  destination { zone_id = terrifi_firewall_zone.guest.id }
}

resource "terrifi_firewall_policy" "block_trusted_to_work" {
  name        = "Block Trusted to Work"
  description = "Your personal devices (and Tailscale clients) cannot reach the work MacBook."
  action      = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.trusted.id }
  destination { zone_id = terrifi_firewall_zone.work.id }
}

resource "terrifi_firewall_policy" "block_iot_to_work" {
  name   = "Block IoT to Work"
  action = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.iot.id }
  destination { zone_id = terrifi_firewall_zone.work.id }
}

resource "terrifi_firewall_policy" "block_iot_quarantine_to_work" {
  name   = "Block IoT-Quarantine to Work"
  action = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.iot_quarantine.id }
  destination { zone_id = terrifi_firewall_zone.work.id }
}

resource "terrifi_firewall_policy" "block_guest_to_work" {
  name   = "Block Guest to Work"
  action = "BLOCK"
  source      { zone_id = terrifi_firewall_zone.guest.id }
  destination { zone_id = terrifi_firewall_zone.work.id }
}

# ---- Optional: Home Assistant push-from-IoT exception ---------------------
# Most HA integrations are pull-based: HA reaches out to the device, replies
# come back through the stateful firewall, and the explicit Trusted → IoT
# ALLOW above covers it. Some integrations are push-based (camera motion webhooks,
# certain Zigbee2MQTT setups, etc.) and the IoT device initiates a
# connection to HA on port 8123. To allow only that:
#
#   1. Find the HA host's static IP (set one in DHCP first).
#   2. Set the variable below to that IP, e.g. "10.1.0.50".
#   3. Uncomment the resource block.
#
# This is intentionally narrow: only HA's IP, only port 8123. If you have
# multiple services that need push-from-IoT, copy the block and add more.
variable "homeassistant_ip" {
  description = "Static IP of the Home Assistant host on the Trusted VLAN. Empty disables the push-from-IoT exception."
  type        = string
  default     = ""
}

# resource "terrifi_firewall_policy" "allow_iot_to_homeassistant" {
#   count = var.homeassistant_ip != "" ? 1 : 0
#
#   name        = "Allow IoT to Home Assistant (push integrations)"
#   description = "Lets IoT devices push events (camera motion, etc.) to HA."
#   action      = "ALLOW"
#   protocol    = "tcp"
#
#   source {
#     zone_id = terrifi_firewall_zone.iot.id
#   }
#   destination {
#     zone_id            = terrifi_firewall_zone.trusted.id
#     ips                = [var.homeassistant_ip]
#     port_matching_type = "SPECIFIC"
#     port               = 8123
#   }
# }
#
# resource "terrifi_firewall_policy_order" "iot_to_trusted_order" {
#   count = var.homeassistant_ip != "" ? 1 : 0
#
#   source_zone_id      = terrifi_firewall_zone.iot.id
#   destination_zone_id = terrifi_firewall_zone.trusted.id
#
#   # ALLOW evaluated first, then the BLOCK catches everything else.
#   policy_ids = [
#     terrifi_firewall_policy.allow_iot_to_homeassistant[0].id,
#     terrifi_firewall_policy.block_iot_to_trusted.id,
#   ]
# }
