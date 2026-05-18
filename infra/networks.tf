# Networks (VLANs)
#
# The UDR-7 ships with a default LAN on VLAN 1. We keep using it as the
# "Trusted" network. Three additional VLANs split off IoT, guests, and a
# camera/quarantine network. Inter-VLAN traffic is then controlled by the
# zone-based firewall in firewall_zones.tf / firewall_policies.tf.
#
# dhcp_enabled = true on every network: the terrifi provider leaves the
# DHCP server OFF unless told otherwise, which leaves clients unable to
# get an IP address. The dhcp_start/dhcp_stop ranges are derived from the
# subnet by the provider (10.<vlan>.0.6 – 10.<vlan>.0.254).

# The default LAN already exists. We import it (see UI-CHECKLIST.md step 4),
# then optionally tighten its subnet here. Comment this resource out on the
# very first apply if you haven't run the import yet — otherwise Terraform
# will refuse to create a network that already exists.
resource "terrifi_network" "trusted" {
  name         = "Trusted"
  purpose      = "corporate"
  subnet       = var.trusted_subnet
  dhcp_enabled = true
}

resource "terrifi_network" "iot" {
  name         = "IoT"
  purpose      = "corporate"
  vlan_id      = var.iot_vlan_id
  subnet       = var.iot_subnet
  dhcp_enabled = true
}

resource "terrifi_network" "iot_quarantine" {
  name         = "IoT-Quarantine"
  purpose      = "corporate"
  vlan_id      = var.iot_quarantine_vlan_id
  subnet       = var.iot_quarantine_subnet
  dhcp_enabled = true
}

resource "terrifi_network" "guest" {
  name         = "Guest"
  purpose      = "corporate"
  vlan_id      = var.guest_vlan_id
  subnet       = var.guest_subnet
  dhcp_enabled = true
}

# Work: fully-isolated VLAN for the work MacBook (Wi-Fi + dedicated wired
# port). Cannot reach any other LAN zone; no other LAN zone can reach it.
# Treated as "corporate" purpose because it's a regular client network,
# not a captive-portal guest network.
resource "terrifi_network" "work" {
  name         = "Work"
  purpose      = "corporate"
  vlan_id      = var.work_vlan_id
  subnet       = var.work_subnet
  dhcp_enabled = true
}
