# NetworkManager OpenVPN Troubleshooting Runbook

This runbook explains how to fix a common issue:

- VPN connects
- Private network works
- Public internet stops working

## Why it happens

NetworkManager OpenVPN can accept a VPN default route from the server.
If the VPN server/profile is not intended for full internet egress, your public internet traffic is sent to the tunnel and fails.

OpenVPN3 CLI can behave differently, so it may still work in the same environment.

## Quick fix (GUI)

In VPN profile settings, for both IPv4 and IPv6:

1. Open Routes.
2. Enable: Use this connection only for resources on its network.
3. Save.
4. Disconnect and reconnect VPN.

Expected result:

- Private network stays reachable through VPN.
- Public internet continues through your normal local gateway.

## Quick fix (CLI)

Replace <PROFILE_NAME> with your VPN connection name.

```bash
nmcli connection modify "<PROFILE_NAME>" ipv4.never-default yes ipv6.never-default yes
```

Reconnect VPN after changing settings.

## Verify current settings

```bash
nmcli -g connection.id,ipv4.never-default,ipv6.never-default,ipv4.ignore-auto-routes,ipv6.ignore-auto-routes connection show "<PROFILE_NAME>"
```

Recommended values for this split-tunnel use case:

- ipv4.never-default: yes
- ipv6.never-default: yes

## Optional DNS fallback checks

If internet still fails after route fix:

1. Keep route fix enabled.
2. Check DNS resolution while connected.

```bash
getent ahosts google.com
```

If DNS fails but IP ping works, tune DNS for the profile (or set DNS servers explicitly).

## One-command restore for this known working profile

```bash
nmcli connection modify "profile-7850987265922162575" ipv4.never-default yes ipv6.never-default yes
```

## Notes

- This runbook is for NetworkManager OpenVPN plugin behavior.
- It does not change OpenVPN3 CLI behavior.
- Avoid running destructive route commands while on remote sessions.
