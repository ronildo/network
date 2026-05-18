# Firewall zones
#
# A zone is a bag of networks that the firewall treats as one trust level.
# Inter-zone traffic is controlled by the policies in firewall_policies.tf.
# Intra-zone (same-zone) traffic is allowed by default.
#
# Prerequisite: the zone-based firewall MUST be turned on in the UI before
# `tofu apply` will succeed. See UI-CHECKLIST.md step 2.
#
# The UDR-7 has built-in zones for "External" (WAN) and "Internal" that we
# do NOT manage with Terraform. Reference them by name in the UI when you
# need to write a policy that targets the WAN.

resource "terrifi_firewall_zone" "trusted" {
  name        = "Trusted"
  network_ids = [terrifi_network.trusted.id]
}

resource "terrifi_firewall_zone" "iot" {
  name        = "IoT"
  network_ids = [terrifi_network.iot.id]
}

resource "terrifi_firewall_zone" "iot_quarantine" {
  name        = "IoT-Quarantine"
  network_ids = [terrifi_network.iot_quarantine.id]
}

resource "terrifi_firewall_zone" "guest" {
  name        = "Guest"
  network_ids = [terrifi_network.guest.id]
}

resource "terrifi_firewall_zone" "work" {
  name        = "Work"
  network_ids = [terrifi_network.work.id]
}
