# Post-apply API fixup for terrifi field gap.
#
# `terraform_data.post_apply_fixups` runs `post-tofu-apply.sh` after every
# `tofu apply`. The script sets `enhanced_iot=false` on the Home-IoT WLAN —
# the one UniFi field that's load-bearing for cross-VLAN traffic and that
# terrifi does not expose. See post-tofu-apply.sh header for the full WHY,
# and firewall_policies.tf GOTCHA #2 for the related stateful-return-path
# fields (which we set declaratively now that we know terrifi exposes them).
#
# Trigger: re-run on every apply (timestamp() trigger). The script is
# idempotent — PUTting enhanced_iot=false when it's already false is a
# no-op on the controller. One extra API call per apply is cheap insurance
# against the controller re-defaulting the field after some future change.
#
# Env vars: the script needs UNIFI_API and UNIFI_API_KEY. local-exec
# inherits the env of the tofu process, so running tofu via
# `op run --env-file=infra/op-env.template -- tofu apply` is enough.

resource "terraform_data" "post_apply_fixups" {
  triggers_replace = {
    always = timestamp()
  }

  depends_on = [
    terrifi_wlan.iot,
    terrifi_firewall_policy.allow_trusted_to_iot,
    terrifi_firewall_policy.allow_trusted_to_iot_quarantine,
    terrifi_firewall_policy.allow_trusted_to_guest,
    terrifi_firewall_policy.block_iot_to_trusted,
    terrifi_firewall_policy.block_quarantine_to_trusted,
    terrifi_firewall_policy.block_guest_to_trusted,
  ]

  provisioner "local-exec" {
    command     = "${path.module}/post-tofu-apply.sh"
    interpreter = ["/bin/bash"]
    # Surface stdout/stderr so the API patch results are visible in tofu output.
    quiet = false
  }
}
