# Provider config is driven entirely by environment variables. The
# canonical way to set them is via 1Password — see README.md → "1Password
# setup", and the `op-env.template` file at the repo root.
#
# Typical command (resolves op:// references and runs tofu in one shot):
#
#   op run --env-file=op-env.template -- tofu plan -out tf.plan
#
# Variables the provider reads:
#
#   UNIFI_API              e.g. https://10.1.0.1
#   UNIFI_API_KEY          API key from the UniFi UI (preferred)
#   UNIFI_USERNAME         alternative: local admin username
#   UNIFI_PASSWORD         alternative: local admin password
#   UNIFI_INSECURE         true   # UDR-7 ships with a self-signed cert
#   UNIFI_RESPONSE_CACHING true   # reduces controller load
#   UNIFI_SITE             default

provider "terrifi" {}
