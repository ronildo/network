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
# Multicast/mDNS reaching from Trusted into IoT (so Sonos/Chromecast/HomeKit
# discovery still works) is handled separately by enabling mDNS Reflector in
# the UI — see UI-CHECKLIST.md step 7.

# ---- IoT cannot reach Trusted ---------------------------------------------
resource "terrifi_firewall_policy" "block_iot_to_trusted" {
  name        = "Block IoT to Trusted"
  description = "Compromised IoT device must not reach personal devices."
  action      = "BLOCK"

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

# Note on Trusted → IoT/Guest/Quarantine: we deliberately do NOT block these.
# You want to be able to reach the printer, smart plug, or camera from your
# laptop. The asymmetry is the point: stateful firewall lets the reply
# packets back, but unsolicited connections from the lower-trust zone don't
# happen. If you ever want to lock this down further, add ALLOW policies
# for specific ports and flip the defaults — but that's a "hardened"
# posture, not balanced.

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
# come back through the stateful firewall, and the Trusted-→-IoT default
# covers it. Some integrations are push-based (camera motion webhooks,
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
