# --- Network layout --------------------------------------------------------
#
# Defaults follow a balanced "home + IoT + guest + camera-quarantine" layout.
# Change subnets / VLAN IDs here if they clash with anything already on your
# LAN. VLAN 1 is the UDR-7 default LAN — don't reuse it for another network.

variable "trusted_subnet" {
  description = "CIDR (with gateway IP) for the trusted/personal-device LAN. Convention: 10.<vlan>.0.0/24."
  type        = string
  default     = "10.1.0.1/24"
}

variable "iot_vlan_id" {
  description = "VLAN ID for the general IoT network (smart speakers, plugs, TVs)."
  type        = number
  default     = 20
}

variable "iot_subnet" {
  description = "CIDR (with gateway IP) for the IoT network."
  type        = string
  default     = "10.20.0.1/24"
}

variable "iot_quarantine_vlan_id" {
  description = "VLAN ID for IoT devices that should be denied internet access (e.g. no-name cameras)."
  type        = number
  default     = 21
}

variable "iot_quarantine_subnet" {
  description = "CIDR (with gateway IP) for the IoT-quarantine network."
  type        = string
  default     = "10.21.0.1/24"
}

variable "guest_vlan_id" {
  description = "VLAN ID for the guest network."
  type        = number
  default     = 30
}

variable "guest_subnet" {
  description = "CIDR (with gateway IP) for the guest network."
  type        = string
  default     = "10.30.0.1/24"
}

variable "work_vlan_id" {
  description = "VLAN ID for the work device network. Fully isolated from everything else."
  type        = number
  default     = 40
}

variable "work_subnet" {
  description = "CIDR (with gateway IP) for the work network."
  type        = string
  default     = "10.40.0.1/24"
}

# --- Wi-Fi -----------------------------------------------------------------
#
# Passphrases come from `terraform.tfvars` (gitignored) OR environment vars:
#   export TF_VAR_trusted_wifi_passphrase=...
#   export TF_VAR_iot_wifi_passphrase=...
#   export TF_VAR_guest_wifi_passphrase=...
#
# Use a password manager to generate 20+ random characters each.
# Use *different* passphrases for each SSID — that's the entire point of
# isolating IoT and guest networks.

variable "trusted_wifi_ssid" {
  description = "SSID for the trusted/personal-device Wi-Fi."
  type        = string
  default     = "Macaroni"
}

variable "trusted_wifi_passphrase" {
  description = "WPA passphrase for the trusted Wi-Fi. 20+ random chars recommended."
  type        = string
  sensitive   = true
}

variable "iot_wifi_ssid" {
  description = "SSID for the IoT Wi-Fi."
  type        = string
  default     = "Home-IoT"
}

variable "iot_wifi_passphrase" {
  description = "WPA passphrase for the IoT Wi-Fi. Long random string; never reuse."
  type        = string
  sensitive   = true
}

variable "iot_quarantine_wifi_ssid" {
  description = "SSID for the IoT-quarantine (no-internet) Wi-Fi."
  type        = string
  default     = "Home-IoT-NoNet"
}

variable "iot_quarantine_wifi_passphrase" {
  description = "WPA passphrase for the IoT-quarantine Wi-Fi."
  type        = string
  sensitive   = true
}

variable "guest_wifi_ssid" {
  description = "SSID for the guest Wi-Fi."
  type        = string
  default     = "Seawatch"
}

variable "guest_wifi_passphrase" {
  description = "WPA passphrase for the guest Wi-Fi. Rotate every few months."
  type        = string
  sensitive   = true
}

variable "work_wifi_ssid" {
  description = "SSID for the work-device Wi-Fi. Don't make it obviously yours from the street."
  type        = string
  default     = "Work"
}

variable "work_wifi_passphrase" {
  description = "WPA passphrase for the work Wi-Fi. Only the work MacBook joins this; pick something long and don't reuse."
  type        = string
  sensitive   = true
}

# --- Posture toggles -------------------------------------------------------

variable "enable_wpa3_transition" {
  description = "Enable WPA3 in transition mode (WPA2/WPA3 mixed) on the trusted SSID. Disable if older devices keep dropping."
  type        = bool
  default     = true
}

variable "block_quarantine_internet" {
  description = "Block all internet egress for the IoT-quarantine zone (recommended for unknown cameras)."
  type        = bool
  default     = true
}
