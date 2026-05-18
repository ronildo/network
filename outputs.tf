output "network_ids" {
  description = "Map of network name to network ID — useful for follow-up imports."
  value = {
    trusted        = terrifi_network.trusted.id
    iot            = terrifi_network.iot.id
    iot_quarantine = terrifi_network.iot_quarantine.id
    guest          = terrifi_network.guest.id
    work           = terrifi_network.work.id
  }
}

output "zone_ids" {
  description = "Map of firewall zone name to zone ID."
  value = {
    trusted        = terrifi_firewall_zone.trusted.id
    iot            = terrifi_firewall_zone.iot.id
    iot_quarantine = terrifi_firewall_zone.iot_quarantine.id
    guest          = terrifi_firewall_zone.guest.id
    work           = terrifi_firewall_zone.work.id
  }
}
