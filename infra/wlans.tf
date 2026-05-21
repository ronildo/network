# Wireless networks (SSIDs)
#
# Each VLAN gets its own SSID with its own passphrase. Devices joining a
# given SSID are placed in the matching VLAN, which is what makes the
# zone-based firewall rules apply.

# Trusted: personal laptops, phones, work devices.
# WPA3 transition mode keeps older WPA2-only devices working while letting
# WPA3-capable devices upgrade automatically.
resource "terrifi_wlan" "trusted" {
  name       = var.trusted_wifi_ssid
  network_id = terrifi_network.trusted.id
  passphrase = var.trusted_wifi_passphrase

  wpa3_support    = var.enable_wpa3_transition
  wpa3_transition = var.enable_wpa3_transition
  wpa_mode        = "wpa2"
  hide_ssid       = false # iOS fails to associate with hidden + WPA3-transition
}

# IoT: smart speakers, smart plugs, TVs, doorbells you trust.
# 2.4 GHz only — almost every IoT chipset is 2.4 GHz, and confining them
# there keeps the 5/6 GHz bands clean for the devices that benefit.
#
# `optimize_iot_connectivity` is OFF, intentionally. The flag enables AP-side
# proxy-ARP + IoT multicast helpers, but on UDR-7 firmware it silently drops
# unicast that was *routed in* from another VLAN to wireless clients on this
# SSID. Symptom when on: off-subnet clients (Trusted laptop, Apple TV HomeKit
# hub on Trusted) cannot reach IoT devices even though the zone firewall
# allows it and the same IoT devices respond fine from another Home-IoT
# client. HomeKit shows "No Response" until the iPhone is moved onto the IoT
# SSID. If you ever flip this to `true` chasing a small connectivity win for
# weak IoT devices, expect HomeKit to break again — leave it off.
#
# RELATED: there is a SECOND per-WLAN IoT-helper field — `enhanced_iot` —
# that has the same class of effect and that terrifi does NOT expose.
# `infra/post-tofu-apply.sh` (run automatically by terraform_data.
# post_apply_fixups) forces it to false via the UniFi API after every
# apply. See firewall_policies.tf GOTCHA #2 for the full picture and
# post_apply.tf for the auto-run wiring.
resource "terrifi_wlan" "iot" {
  name       = var.iot_wifi_ssid
  network_id = terrifi_network.iot.id
  passphrase = var.iot_wifi_passphrase

  # `application = "standard"` (not "iot"). On UDR-7 firmware, setting
  # application = "iot" enables an enhanced_iot side-effect that terrifi
  # does not expose and that re-breaks cross-VLAN traffic (see
  # firewall_policies.tf GOTCHA #2). We keep optimize_iot_connectivity
  # below explicitly disabled too — same reason.
  application              = "standard"
  optimize_iot_connectivity = false
  wifi_band                = "2g"
  wpa_mode                 = "wpa2"
}

# IoT-Quarantine: no-name cameras / devices you don't trust to reach the
# internet. Same 2.4 GHz IoT treatment, but firewall rules cut external
# egress (see firewall_policies.tf).
resource "terrifi_wlan" "iot_quarantine" {
  name       = var.iot_quarantine_wifi_ssid
  network_id = terrifi_network.iot_quarantine.id
  passphrase = var.iot_quarantine_wifi_passphrase

  application              = "iot"
  optimize_iot_connectivity = true
  wifi_band                = "2g"
  wpa_mode                 = "wpa2"
  hide_ssid                = true # not security, but reduces accidental joins
}

# Guest: visitors. Captive-portal behavior comes from application = "hotspot".
# WPA2 with a shared passphrase is intentionally low-friction. Rotate it
# every few months — change var.guest_wifi_passphrase and `tofu apply`.
resource "terrifi_wlan" "guest" {
  name       = var.guest_wifi_ssid
  network_id = terrifi_network.guest.id
  passphrase = var.guest_wifi_passphrase

  application = "hotspot"
  wpa_mode    = "wpa2"
}

# Work: the work MacBook joins this and nothing else does. Modern laptop,
# so WPA3 transition is safe. Standard (not hotspot) application — we want
# normal client behavior, not captive-portal interception.
resource "terrifi_wlan" "work" {
  name       = var.work_wifi_ssid
  network_id = terrifi_network.work.id
  passphrase = var.work_wifi_passphrase

  wpa3_support    = true
  wpa3_transition = true
  wpa_mode        = "wpa2"
}
