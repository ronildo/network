# UDR-7 manual UI steps

The Terrifi Terraform provider covers networks, Wi-Fi, and the zone-based
firewall. Everything else has to be done in the UniFi UI — either because
the provider doesn't expose it, or because it has to happen once at the
start before the API even exists.

Steps run in order. Where you see `[required for terraform]`, that step is
a prerequisite for `tofu apply` to work.

Network layout assumed by this checklist (override in `terraform.tfvars`):

| VLAN | Subnet | Gateway |
|---|---|---|
| 1 — Trusted | `10.1.0.0/24` | `10.1.0.1` |
| 20 — IoT | `10.20.0.0/24` | `10.20.0.1` |
| 21 — IoT-Quarantine | `10.21.0.0/24` | `10.21.0.1` |
| 30 — Guest | `10.30.0.0/24` | `10.30.0.1` |
| 40 — Work | `10.40.0.0/24` | `10.40.0.1` |

---

## Phase 1 — Initial bootstrap (do these before touching Terraform)

### 1. Adopt the device and set up the admin account
Connect a laptop to a LAN port on the UDR-7. The device ships with
`192.168.1.1` as its default LAN — open `https://192.168.1.1` and run the
setup wizard.

- **Use a local-account admin, not just the cloud SSO.** If your Ubiquiti
  cloud account ever gets compromised, a local admin is your offline way
  back in.
- **Password 20+ random characters**, stored in a password manager.
- **Turn on two-factor auth** for the cloud account (UI → Console
  Settings → Admins → your-name → Two-factor).
- **Disable Remote Access** (Console Settings → Remote Access → off).
  Tailscale (step 9) is a better path back to your network.

### 2. Renumber the default LAN to 10.1.0.0/24
The UDR-7 ships its default LAN on `192.168.1.0/24`. Since we want the
whole network on `10.x.x.x`, change it now — before adding anything else,
and before importing the network into Terraform.

UI → Settings → Networks → **Default** → set:
- **Gateway IP / Subnet**: `10.1.0.1/24`
- **DHCP range**: `10.1.0.100 – 10.1.0.250` (or whatever you like)

The router's management IP changes to `10.1.0.1`. Your laptop will lose
its DHCP lease, take a moment to renew, then you can reach the UI again at
`https://10.1.0.1`.

### 3. Update firmware before anything else `[required for terraform]`
UI → System → Updates → Install updates. The UDR-7 ships with whatever
firmware was current when it was packaged, and a brand-new device can be
many revisions behind. The zone-based firewall API in particular got
significantly more stable through 2025.

After firmware updates, the device reboots — give it ~5 minutes before
continuing.

### 4. Enable the zone-based firewall `[required for terraform]`
UI → Settings → Security → Traffic & Firewall Rules → **Upgrade to the
New Zone-Based Firewall**.

This is a one-way migration. It creates the default `Internal` /
`External` / `VPN` zones and turns on the v2 firewall API that Terraform
uses. Without this step, every `terrifi_firewall_zone` / `terrifi_firewall_policy`
apply will 400-error.

### 5. Create the local API admin and generate an API key `[required for terraform]`
UI → Settings → Admins & Users → **Admins** → Create New Admin.

- **Role**: Site Admin (Network only). It needs write access to networks,
  Wi-Fi, and the firewall; nothing else.
- **Restrict to Local Access Only** — disable cloud login for this account.
  This account is for the API, not for you.
- **MFA**: skip — service accounts can't do interactive 2FA.

Once the admin exists, log in as them, go to **Control Plane → Admins →
your-api-user → API Keys → Create**. Copy the key once — it's not shown
again. Paste it directly into the **`api_key`** field of the `UDR-7`
1Password item (see README → "1Password setup" for the field layout).

Also drop the controller URL (`https://10.1.0.1` once you've completed
step 2) into the `api_url` field of the same item.

You'll never need to export these as shell variables — `op run`
(documented in the README) reads them from 1Password at the moment each
`tofu` command runs.

### 6. Adopt the default LAN into Terraform state
The UDR-7 already created a default LAN on VLAN 1 (now `10.1.0.0/24`
after step 2). If you run `tofu apply` without telling Terraform about
it, Terraform will try to create a second network and the API will 409.
Use the Terrifi CLI to generate import blocks:

```sh
go install github.com/alexklibisz/terrifi/cmd/terrifi@latest
terrifi generate-imports terrifi_network >> imports.tf
```

Edit `imports.tf` so the `to =` reference for the default LAN points at
`terrifi_network.trusted`, then `tofu plan` to confirm it's a no-op
import.

Alternative: comment out the `terrifi_network "trusted"` block in
`networks.tf` for the first apply, then bring it back in once the import
is done.

---

## Phase 2 — Now run Terraform

See `README.md` for the exact commands. Come back here when `tofu apply`
finishes cleanly.

---

## Phase 3 — Finishing touches (UI only)

### 7. Turn on the IDS/IPS engine
UI → Settings → Security → **Threat Management** → set to **Detect and Block**.

The UDR-7 advertises 2.3 Gbps IDS/IPS throughput, which is faster than
almost any home internet connection, so the performance hit is negligible.

Pick the category set:
- **Recommended for "balanced":** turn on *Emerging Threats*,
  *Malware-CnC*, *Exploit-Kit*, *Hacking*. Leave the high-noise
  categories (*Chat*, *Games*) off.

### 8. Enable mDNS Reflector between Trusted and IoT
UI → Settings → Networks → **Multicast DNS Reflector** → enable, and pick
the networks that need to see each other's mDNS broadcasts.

For your setup, you want **Trusted ↔ IoT** specifically:
- Home Assistant integrations that auto-discover devices (HomeKit, Cast,
  Sonos, ESPHome, Shelly) rely on mDNS. Without the reflector, your IoT
  devices live on a different VLAN from HA and discovery silently fails.
- Casting from your phone (Trusted) to a Chromecast or Sonos (IoT)
  needs the same.

Leave **Guest**, **IoT-Quarantine**, and **Work** OFF. Visitors don't
need to see your printer; quarantined cameras don't need to be
discoverable; the work MacBook shouldn't see *any* of your home stuff,
discovery included.

### 9. Tailscale: keep your subnet router happy
You already have Tailscale running on your Linux homelab host, advertising
the LAN subnet. The UDR-7 doesn't need much from you to support it, but:

- **No port forward is required.** Tailscale uses outbound NAT traversal.
  If you ever feel tempted to forward a port "to make Tailscale work,"
  stop — that's a sign the host's outbound traffic is being blocked,
  not that you need an inbound rule.
- **Static IP for the Tailscale host.** UI → Settings → Networks →
  Default → DHCP → Static Leases. Pin the homelab host to e.g.
  `10.1.0.10`. This means the same IP shows up in `tailscale status`
  every time, and any device-specific firewall rules you write
  (including the optional Home Assistant exception in
  `firewall_policies.tf`) are stable.
- **Advertised routes.** On the host, the Tailscale daemon needs
  `--advertise-routes=10.1.0.0/24,10.20.0.0/24` (or whichever subnets
  your remote devices need to reach). Approve them in the Tailscale
  admin console.
- **ACLs.** In the Tailscale admin console, your tailnet ACLs are what
  actually decide which Tailscale clients can hit which LAN IPs. The
  UDR-7 firewall sees that traffic as coming *from the subnet-router
  host* (so on the Trusted zone), which means LAN-side rules treat it
  as Trusted. Keep your tailnet ACLs tight — anything that talks to
  your tailnet inherits Trusted-level reach.
- **No second VPN.** WireGuard server on the UDR-7 is intentionally
  not set up. Two overlapping VPNs is more attack surface, not less.

### 10. Schedule UDR-7 config backups to the NAS
UI → System → Backups → **Auto Backup** → enable, then **Backup Storage** →
add **SMB** (or NFS, whichever your NAS prefers).

- Point it at a folder on the NAS dedicated to network backups, e.g.
  `\\nas\backups\udr7`.
- Use a service account on the NAS that only has write access to that
  folder — don't reuse your admin credentials.
- Frequency: daily. Retain at least 14.

Restoring from one of these backups brings back IDS/IPS settings, port
forwards, the WireGuard server (if you ever add one), mDNS settings, and
the Tailscale-related static leases — i.e. everything Terraform does NOT
manage. The Terraform state and the NAS backups together are your full
DR story.

### 11. Turn on DNS over HTTPS for the router
UI → Settings → Internet → WAN → **DNS** → set to a DoH-capable provider
(Cloudflare `1.1.1.1` over HTTPS, Quad9 `9.9.9.9`, etc.) and enable the
DoH toggle.

This protects DNS lookups from passive snooping on your ISP's path.

Note: if Home Assistant uses Pi-hole or AdGuard on the homelab host,
point the UDR-7's clients at it via **Settings → Networks → Trusted →
DHCP → DNS Server** instead, and keep DoH on the UDR-7 itself so that
Pi-hole's upstream is encrypted.

### 12. Work device — wired access via the office switch

The Wi-Fi side is handled by Terraform: the work MacBook joins the
**Work** SSID and lands on VLAN 40 with no visibility into home gear.

For wired, you already have everything you need. The UniFi USW Flex
2.5G 5 in the office is uplinked to the UDR-7 (its port 5 → UDR-7
port 3), and your office gear (NAS, homelab, personal computer) all
sits on the four downlink ports. The trick is just: dedicate one
switch port to the Work VLAN, plug the work MacBook into it.

This is simpler than the "share one cable" approaches we'd need without
the switch — no macOS VLAN tagging, no profile-swap dance. The personal
computer stays on its existing port; the work MacBook gets its own; both
can be plugged in simultaneously, each on its own VLAN.

**Setup (one-time):**

1. **Create the port profile.** UI → Settings → Profiles → **Port
   Profiles** → Create:
   - Name: `Work-Access`
   - Native Network: `Work` (untagged)
   - Tagged Networks: *(none — pure access port for VLAN 40)*

2. **Apply it to one switch port.** UI → UniFi Devices → **USW Flex
   2.5G 5** → Ports → pick a free port → set profile to `Work-Access`.

   Which port? Use a GbE port (1, 2, or 4) for the MacBook — typical
   work loads don't need 2.5 GbE, and you may want to keep port 3
   (the only non-uplink 2.5 GbE port) free for the NAS if it's not
   already there. Don't touch port 5 — that's your uplink to the UDR-7.

3. **Confirm the uplink port is a trunk.** UI → UniFi Devices → USW
   Flex 2.5G 5 → Port 5 → profile should be `All` (or the
   auto-detected trunk profile, which carries every VLAN). UniFi
   usually sets this automatically when a switch is adopted; verify
   anyway. If it's not, set the profile to `All`.

4. **Plug in.** Work MacBook → USB-C-to-Ethernet adapter → the
   `Work-Access` switch port. macOS DHCPs an address in `10.40.0.0/24`
   and you're done. Verify in **System Settings → Network**: the
   wired interface shows a `10.40.0.x` address.

**If all 4 downlink ports are already in use:**

- Most common fix: if you have a wired printer on the switch, move it
  to Wi-Fi on the **IoT** SSID — printers are exactly what the IoT
  VLAN is for, and HA can still reach it because Trusted → IoT is
  allowed.
- Or skip wired for work entirely — the Work SSID lives on the same
  VLAN 40 anyway, with the same isolation. Wi-Fi 7 from the UDR-7
  hits 5+ Gbps on the 6 GHz band, which beats most home internet.
- Or get a small second switch dedicated to work (cheapest answer if
  you have a multi-monitor / wired-peripheral situation that needs
  the wired bandwidth).

**Verification:**

- Work MacBook on the `Work-Access` port: gets a `10.40.0.x` IP,
  reaches the internet ✓
- Work MacBook: `ping 10.1.0.10` (homelab) → no reply ✓
- Work MacBook: `ping 10.1.0.1` (UDR-7 gateway from the *home* side) →
  no reply ✓ (Work gets its own gateway `10.40.0.1`)
- Personal computer on its existing switch port: still `10.1.0.x`,
  unchanged ✓
- Trusted laptop: `ping 10.40.0.x` (work MacBook) → no reply ✓
  (the symmetric block in both directions)

### 13. Port forwards (only if you actually need them)
UI → Settings → Security → **Port Forwarding**.

**Default answer: don't.** Tailscale already gives you reachability from
outside. Almost everything you'd want a port forward for — SSH to the
homelab, the Home Assistant UI, the NAS, Frigate, whatever — is already
on your tailnet.

If you genuinely need a forward (game server, public webhook receiver):
- Forward to a fixed IP in the `Trusted` network. Never forward to an IoT
  device.
- Restrict the **Source** field to a specific IP / CIDR if at all
  possible. A wide-open forward is a much bigger risk than the Tailscale
  alternative.

### 14. Wi-Fi PSK rotation reminder
The Terraform config pulls passphrases from 1Password at apply time. To rotate:

1. In 1Password, open the `UDR-7` item and regenerate the relevant
   `wifi_*_passphrase` field (use 1P's password generator — 24 chars,
   no symbols if you want to type it on a TV remote).
2. `op run --env-file=op-env.template -- tofu apply` — Terraform sees
   the new value, pushes it to the controller.
3. Update your devices with the new passphrase from 1Password.

Rotate **guest** at least every 6 months. Rotate **iot_quarantine** if you
add a new no-name device. **Trusted** only needs rotation if you suspect
the passphrase leaked.

### 15. Verify it's all working
- `https://10.1.0.1` (Trusted laptop): full UI access ✓
- Trusted laptop → homelab host (`10.1.0.10`) and NAS: reachable ✓
- Phone on the IoT SSID: can reach the internet, **cannot** reach
  `10.1.0.x` ✓
- Home Assistant (Trusted) reaches its smart bulbs / plugs (IoT) ✓
- HomeKit / Cast / Sonos discovery on Trusted finds IoT devices ✓
  (if not, double-check step 8 mDNS Reflector covers Trusted ↔ IoT)
- Phone on the Guest SSID: can reach the internet, **cannot** reach
  `10.1.0.x`, `10.20.0.x`, `10.21.0.x` ✓
- Camera on IoT-Quarantine SSID: **cannot** reach the internet ✓
  (use a watch-only test camera; check the UDR-7 traffic chart shows
  no outbound for its IP)
- Phone off-network (cellular, Tailscale on): reaches `10.1.0.1`,
  the homelab, and the NAS through the subnet router ✓
- Work MacBook on the Work SSID (or its dedicated wired port): can
  reach the internet, **cannot** ping `10.1.0.x` / `10.20.0.x` /
  `10.21.0.x` / `10.30.0.x` ✓
- Trusted laptop: **cannot** ping the work MacBook's `10.40.0.x` IP ✓
  (the asymmetry from Trusted → IoT is *not* present for Work — this
  is the deliberate "fully isolated, both directions" behavior)
