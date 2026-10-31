---
name: dsh-pocket-remote
description: Install, configure, or repair phone access to DeepSeek Harness through the dsh-pocket plugin 鈥?scan a QR and use the same DSH UI from a phone on LAN or 4G, including HarmonyOS NEXT where APKs cannot be installed. Use whenever the user mentions 鎵嬫満璁块棶, 鎵嬫満杩?DSH, 鎵爜, 鍏綉璁块棶, dsh-pocket, 鎵嬫満涓婂彂浠诲姟, 楦胯挋鎵嬫満, 閰嶅澶辫触, 瀵嗙爜閿欒, error 1033, error 530, or asks how to reach their DSH from outside the house.
---

# Phone access to DSH via dsh-pocket

Gives a phone the **real DSH web UI** (not a re-implementation) over LAN or the
public internet. Works on every phone with a browser, which is the only option
on HarmonyOS NEXT 鈥?it cannot install Android APKs, so the native-app gateway
plugins are dead ends there.

## Why dsh-pocket and not a mobile gateway plugin

`dsh-plugin-mobile-gateway` speaks its own WebSocket protocol to an Android/iOS
app. On HarmonyOS NEXT the APK cannot be installed at all, so every network
diagnosis is wasted effort. dsh-pocket reverse-proxies the actual web UI to a
port, and the phone just opens a URL.

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install-pocket.ps1
```

Options: `-Profile desktop` (default), `-Version latest`, `-DryRun`.

It handles the two traps that silently break installation:

| Trap | Symptom |
|---|---|
| `HTTP_PROXY` set to a local socks5 proxy | pnpm hangs minutes, then `ERR_PNPM_META_FETCH_FAIL` |
| Plugin manager fails to write the bundle row | package installs but the 鎵嬫満璁块棶 entry never appears |

Restart DSH afterwards 鈥?the plugin's JS loads at host start.

## Set a fixed PIN (do this every time)

**By default the public PIN is regenerated every time a Quick Tunnel becomes
ready.** A QR scanned two minutes ago then fails with 瀵嗙爜閿欒 even though
nothing looks changed. Pin it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/set-pocket-pin.ps1 -Pin YourPin12345
```

Rules: 8鈥?4 chars, letters and digits only. It writes `token` plus
`publicPinCustom: true`, which makes the rotation a no-op. Restart DSH to apply.

## Use it

1. DSH 鈫?**璁剧疆 鈫?鎵嬫満璁块棶**
2. **灞€鍩熺綉**: scan the local QR (same Wi-Fi)
3. **鍏綉**: 寮€鍚叕缃戣闂?鈫?accept the disclaimer 鈫?scan the public QR
4. The QR already carries the PIN (`?token=<pin>`), so scanning lands directly in
   the UI without typing it

The public address changes on every DSH restart. **Always scan the QR shown in
the panel right now** 鈥?never one from an earlier session or a screenshot.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| **error 1033** | Cloudflare edge has no live tunnel for that hostname | The QR is stale or the tunnel process died. Re-scan the panel's current QR. |
| **error 530** | Tunnel registered but its data path is broken | Almost always the machine's proxy/VPN (Clash, v2ray, sing-box) intercepting the tunnel. Close its TUN mode, or add `*.argotunnel.com` / `*.trycloudflare.com` to its direct rules, then reopen 鍏綉璁块棶. |
| 瀵嗙爜閿欒 | PIN rotated, or the LAN PIN was used on a public URL | They are different PINs: `token` = public, `token-lan` = LAN. Pin both, or scan the QR so the right one is embedded. |
| 鎵嬫満璁块棶 entry missing | Bundle row never written | Re-run `install-pocket.ps1`; it repairs the row. |
| 闅ч亾杩涚▼閫€鍑?(code=4294967295) | Something force-killed `cloudflared` | Only one manager may own the tunnel. Do not run a second tunnel script alongside the plugin. |
| LAN loads but subresources 401 | Browser refused the cookie | Safari on plain `http://` + bare IP is the known case. Use the HTTPS public entry, or Chrome. |

### Never run two tunnel managers

A second `cloudflared` (for example a script that rebuilds the tunnel on a timer)
will fight the plugin: whichever runs `Stop-Process cloudflared` kills the
other's process, the panel keeps showing the now-dead address, and every scan
returns 1033. Let the plugin own the tunnel.

`scripts/pocket-tunnel.ps1` exists only as a **fallback** for when the plugin's
own tunnel cannot work at all: it runs an independent cloudflared with explicit
`--protocol quic` (QUIC is UDP, so it ignores HTTP proxies entirely) and can
render a QR to a file. If you use it, disable the plugin's public access first.

## Company / restricted networks

Corporate networks usually block the outbound paths a tunnel needs. Symptoms:
tunnel registers then 530s, or 1033 forever. Options, best first:

1. Ask IT to allow outbound HTTPS to `*.argotunnel.com` and `*.trycloudflare.com`
2. Use a phone hotspot: phone shares 4G, computer joins it, then use the **LAN**
   QR 鈥?same result, no corporate firewall involved
3. Use LAN only at the office

## Files and state

| Path | Meaning |
|---|---|
| `~/.dsh/dsh-pocket/token` | public PIN |
| `~/.dsh/dsh-pocket/token-lan` | LAN PIN |
| `~/.dsh/dsh-pocket/settings.json` | `publicPinCustom` / `lanPinCustom` flags |
| `~/.dsh/dsh-pocket/tunnel-auto.json` | tunnel auto-restore marker |
| `~/.dsh/dsh-pocket/bin/cloudflared.exe` | pinned cloudflared binary |

