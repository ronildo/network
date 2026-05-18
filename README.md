# UDR-7 home network (balanced-security baseline)

Terraform / OpenTofu config that builds a 5-VLAN, 5-SSID, zone-isolated
home network on a UniFi Dream Router 7 (living room) plus a UniFi USW
Flex 2.5G 5 in the office. Built around a homelab Linux host (Home
Assistant + other services, Tailscale subnet router), a NAS, and a
fully-isolated VLAN for a corporate work MacBook. Plus a manual
checklist for the bits the API doesn't expose.

**Physical topology**

```
                  ┌──────────────────────┐
   Internet ──────┤  UDR-7 (living room) │── Wi-Fi (5 SSIDs)
                  └──────┬───────────────┘
                         │ 2.5 GbE (port 3 → port 5)
                  ┌──────┴───────────────┐
                  │  USW Flex 2.5G 5     │
                  │  (office)            │
                  └─┬──┬──┬──┬───────────┘
                    │  │  │  │
                  NAS  HA  PC Work MacBook
                            (when at desk)
```

## What this gives you

| VLAN | Subnet | What lives here |
|---|---|---|
| 1 — Trusted | `10.1.0.0/24` | Laptops, phones, homelab host, NAS, printer |
| 20 — IoT | `10.20.0.0/24` | Smart speakers, plugs, TVs, doorbells — 2.4 GHz SSID |
| 21 — IoT-Quarantine | `10.21.0.0/24` | No-name cameras — hidden SSID, no internet |
| 30 — Guest | `10.30.0.0/24` | Visitors — captive-portal SSID, internet only |
| 40 — Work | `10.40.0.0/24` | Work MacBook only — Wi-Fi + dedicated port on the office switch; totally isolated both directions |

- WPA3 transition mode on the Trusted SSID, plain WPA2 elsewhere for
  device compatibility.
- Zone-based firewall: lower-trust zones can't initiate to higher-trust
  zones; intra-zone stays open.
- `Trusted → IoT` deliberately allowed so Home Assistant on the homelab
  host can reach smart-home devices to control them.
- IoT-Quarantine has internet egress blocked (once you set `external_zone_id`).
- `Work` is the one zone that's blocked in *both* directions: nothing
  on Trusted/IoT/etc. can reach the work MacBook, and the work MacBook
  can't reach anything on home VLANs. Internet only.

The UI checklist adds: IDS/IPS, DNS-over-HTTPS, Tailscale guidance,
mDNS reflector for Home Assistant discovery, scheduled config backups to
the NAS, and a verification suite.

## Layout

```
.
├── versions.tf              # Terraform + Terrifi provider versions
├── providers.tf             # Reads UNIFI_* env vars; no secrets in file
├── variables.tf             # Subnets, VLAN IDs, SSIDs, passphrases
├── terraform.tfvars.example # Copy → terraform.tfvars, fill in secrets
├── networks.tf              # 4 VLANs
├── wlans.tf                 # 4 SSIDs, one per VLAN
├── firewall_zones.tf        # 4 zones, one per VLAN
├── firewall_policies.tf     # 9 BLOCK policies + optional HA exception
├── outputs.tf               # Network/zone IDs for follow-up imports
├── UI-CHECKLIST.md          # Everything that has to happen in the UI
└── README.md                # this file
```

## Bootstrap, end to end

### One-time, in the UDR-7 UI
Do all of [Phase 1 in UI-CHECKLIST.md](./UI-CHECKLIST.md#phase-1--initial-bootstrap-do-these-before-touching-terraform)
first. The critical steps:

1. Adopt device, set up local admin, disable Remote Access.
2. **Renumber default LAN to `10.1.0.1/24`** (you're switching off the
   factory `192.168.1.x`).
3. Update firmware.
4. **Enable the zone-based firewall** (one-way switch).
5. **Create API admin + generate API key.**
6. Pin a static lease for the homelab host (recommended: `10.1.0.10`).
7. Import the default LAN into Terraform state, OR temporarily comment
   out the `trusted` network block for the first apply.

### One-time, on your workstation

```sh
# OpenTofu (preferred) — open source, drop-in for Terraform
brew install opentofu

# 1Password CLI — used to inject secrets at run time
brew install 1password-cli
# Then: 1Password app → Settings → Developer → enable
# "Integrate with 1Password CLI" so every `op` command unlocks via Touch ID.

# (Optional) Terrifi CLI — used for generating import blocks
go install github.com/alexklibisz/terrifi/cmd/terrifi@latest
```

### 1Password setup (one-time)

All secrets live in a single 1Password item. The repo only stores
*references* to fields, never values — that's `op-env.template` in this
directory, which is safe to commit.

1. In 1Password, create a vault called **Homelab** (or pick an existing
   one — just remember to update the vault name in `op-env.template`).
2. In that vault, create a **Login** item called **UDR-7**.
3. Add the following custom fields (use the "Add new field" link in
   the item editor). All should be set to **Password** type so 1Password
   masks and generates them appropriately.

   | Field name                       | What goes in it                                            |
   |----------------------------------|------------------------------------------------------------|
   | `api_url`                        | `https://10.1.0.1` (or whatever your UDR-7 management IP is) |
   | `api_key`                        | API key generated in UI checklist step 5                   |
   | `wifi_trusted_passphrase`        | 20+ random chars — let 1Password generate it               |
   | `wifi_iot_passphrase`            | different 20+ random chars                                 |
   | `wifi_iot_quarantine_passphrase` | different 20+ random chars                                 |
   | `wifi_guest_passphrase`          | different 20+ random chars (rotate every 6 months)         |
   | `wifi_work_passphrase`           | different 20+ random chars                                 |

4. Sanity check the references resolve:

   ```sh
   op read "op://Homelab/UDR-7/api_key"
   ```

   You'll get a Touch ID prompt; on success it prints the API key.

That's it. The `op-env.template` file in the repo references these
exact field names. If you renamed the vault or item, edit the file
accordingly (find-replace `Homelab` and `UDR-7`).

### Each time you run it

```sh
cd ~/developer/network

# Sanity check the provider can reach the controller.
op run --env-file=op-env.template -- terrifi check-connection

# Initialise providers (once, and again whenever versions.tf changes).
tofu init

# Plan
op run --env-file=op-env.template -- tofu plan -out tf.plan

# Apply
op run --env-file=op-env.template -- tofu apply tf.plan
```

Each `op run` call resolves the `op://` references, populates the env
for the wrapped command only, and tears the env down when the command
exits. Nothing gets persisted to your shell, `~/.zshrc`, history, or
disk. Touch ID prompts you once per invocation if the desktop app has
locked since last use.

**Shorter aliases.** If you'll be running this often, drop something
like this in your `.zshrc`:

```sh
alias tofu-net='op run --env-file=$HOME/developer/network/op-env.template --'
# usage: tofu-net tofu plan -out tf.plan
```

After the first apply, do all of [Phase 3 in UI-CHECKLIST.md](./UI-CHECKLIST.md#phase-3--finishing-touches-ui-only):
IDS/IPS, mDNS reflector, Tailscale checks, NAS backup schedule, DoH,
PSK rotation reminders, verification.

## Home Assistant, NAS, and Tailscale notes

- **Home Assistant** sits on the Trusted zone alongside your laptops.
  The default firewall design already allows Trusted → IoT, so HA can
  reach smart bulbs and the like with no extra rules.
- **Push-based HA integrations** (camera motion webhooks etc.) need the
  reverse direction — IoT → HA on port 8123. There's a commented-out
  template in `firewall_policies.tf`. Set `homeassistant_ip` and
  uncomment it if you need it.
- **NAS** is also on Trusted. UDR-7 config backups should be scheduled
  to an SMB/NFS share on the NAS — see UI-CHECKLIST step 10.
- **Tailscale subnet router** runs on the homelab host. The UDR-7
  doesn't need to know about Tailscale (no port forwards, no firewall
  rules); traffic from your tailnet appears to originate from the
  Linux host's Trusted IP. ACLs in the Tailscale admin console are what
  actually gate who can reach what.

## Day-2 changes

Almost everything is in `variables.tf` or one of the resource files.

- **Rotate a Wi-Fi passphrase**: change the var, `tofu apply`.
- **Add a new VLAN**: copy a block in `networks.tf` + `wlans.tf` +
  `firewall_zones.tf`, add the BLOCK rules in `firewall_policies.tf`.
- **Allow a specific device through a firewall block**: add a higher-
  precedence ALLOW policy *and* a `terrifi_firewall_policy_order` to put
  it before the BLOCK. The HA exception in `firewall_policies.tf` is a
  worked example.
- **Lock things down further** ("hardened" posture): add BLOCK policies
  from Trusted into each lower zone too, then ALLOW only the specific
  destination ports you actually need (DNS, HTTPS, mDNS, HA port, etc.).

## Disaster recovery

State lives in `terraform.tfstate` (gitignored). Two options:

1. **Local + NAS backup**: `cp terraform.tfstate $NAS_MOUNT/backups/network/terraform.tfstate.$(date +%F)`
   after every apply. Pairs naturally with the UDR-7 config backups
   going to the same NAS.
2. **Remote state** (more robust): point `terraform { backend "s3" ... }`
   at an encrypted bucket — see [OpenTofu backend docs](https://opentofu.org/docs/language/settings/backends/s3/).

If you lose state entirely:
- The UI is the source of truth — your actual network keeps working.
- Use `terrifi generate-imports <resource>` to regenerate `import {}`
  blocks for every resource and reattach state.

If you lose the controller itself (UDR-7 dies, factory reset):
- Restore the most recent UI backup from the NAS (UI-CHECKLIST step 10)
  — that brings back IDS settings, port forwards, mDNS, static leases,
  etc.
- Then run `tofu apply` against the restored controller to confirm
  Terraform-managed resources still match.

## Why these choices

| Decision | Why |
|---|---|
| Terrifi over paultyng/filipowm/ubiquiti-community | Actively maintained in 2026, hardware-in-loop tested, supports the v2 zone-based firewall API the UDR-7 uses. The older providers crashed on basic operations. ([source](https://alexklibisz.com/2026/03/07/terrifi)) |
| Zone-based firewall, not legacy LAN-in/LAN-out rules | The UDR-7 ships with ZBF as the recommended model and the legacy interface is being phased out. ([UniFi docs](https://help.ui.com/hc/en-us/articles/115003173168-Zone-Based-Firewalls-in-UniFi)) |
| 10.<vlan>.0.0/24 addressing | `192.168.x` is the default everywhere and clashes with hotel/office networks (and breaks Tailscale routing if a remote network reuses the same range). `10.<vlan>.0.0/24` is unambiguous and reads the VLAN ID off the second octet. |
| 4 VLANs (not 2) | Lets you isolate cameras-that-shouldn't-phone-home separately from cameras-that-should. Hard to add later without renumbering. |
| Homelab + NAS on Trusted (not a dedicated Services VLAN) | Simplest design for a one-server-one-NAS setup. No extra ALLOW rules needed for laptop → NAS or HA → IoT. Worth revisiting if the lab grows. |
| Tailscale, not WireGuard on the UDR-7 | Tailscale needs no inbound port, supports MagicDNS and ACLs, and you already have it. A second VPN is more attack surface, not less. |
| WPA3 *transition* mode, not WPA3-only | A single WPA2-only legacy device (old printer, Sonos Play:1) will fail to join a pure-WPA3 SSID. Transition mode gives you WPA3 where supported and WPA2 fallback elsewhere. |
| API key, not username/password | Less rate-limiting, can be revoked individually, doesn't trip MFA. ([source](https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager)) |
| Trusted → IoT is *not* blocked | Stateful firewall: replies still come back through the IoT→Trusted block, but Home Assistant can reach your printer/bulbs/camera. Symmetric blocking is a "hardened" posture, not balanced. |
| Work zone uses symmetric blocking (unlike the others) | The work MacBook is the one device you actively don't want talking to home gear AND you don't want home gear talking to either — corporate MDM might enumerate, network scanners might run, and you'd rather not show up on either side's logs. So Work blocks both directions. |
| Wired Work access via a dedicated switch port | Office already has a UniFi USW Flex 2.5G 5 uplinked to the UDR-7. One downlink port is set to the `Work-Access` profile (untagged VLAN 40); the work MacBook plugs into it directly. Personal computer stays on its own port — both connected at once, no swap, no tagging. UI-CHECKLIST step 12 has the setup. |

## Sources

- [UDR-7 tech specs](https://techspecs.ui.com/unifi/cloud-gateways/udr7)
- [Terrifi provider](https://github.com/alexklibisz/terraform-provider-terrifi) + [introductory post](https://alexklibisz.com/2026/03/07/terrifi)
- [Terrifi docs](https://github.com/alexklibisz/terraform-provider-terrifi/blob/main/docs/index.md)
- [UniFi Zone-Based Firewall](https://help.ui.com/hc/en-us/articles/115003173168-Zone-Based-Firewalls-in-UniFi)
- [UniFi API authentication options](https://artofwifi.net/blog/unifi-api-authentication-local-admin-vs-api-key-vs-site-manager)
