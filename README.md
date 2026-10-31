# dsh-pocket-remote

An Agent Skill that gives a phone access to **DeepSeek Harness** through
[`dsh-pocket`](https://github.com/shaobeichen/dsh-pocket) 鈥?scan a QR and use the
real DSH UI from a phone on the same Wi-Fi or on 4G.

Built while getting this working on a **HarmonyOS NEXT** phone, where the
Android/iOS mobile-gateway apps cannot be installed at all. dsh-pocket serves the
actual web UI to a port, so any phone with a browser works and there is no app to
install, sign, or sideload.

## Install the skill

```powershell
git clone https://github.com/mglprogram/dsh-pocket-remote "$env:USERPROFILE\.agents\skills\dsh-pocket-remote"
```

Then tell your agent:

> Use the `dsh-pocket-remote` skill to set up phone access to this DSH

## What it does

```powershell
# 1. install / repair the plugin (idempotent)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-pocket.ps1

# 2. pin the PIN so it stops rotating (do this every time)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\set-pocket-pin.ps1 -Pin YourPin12345

# 3. restart DSH, then 璁剧疆 鈫?鎵嬫満璁块棶 鈫?scan the QR shown there
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\restart-dsh.ps1
```

## The four traps this exists to avoid

| Trap | What you see |
|---|---|
| `HTTP_PROXY` points at a local socks5 proxy | pnpm hangs for minutes, then `ERR_PNPM_META_FETCH_FAIL` |
| Plugin manager skips the bundle row | package installs, but **鎵嬫満璁块棶** never appears in Settings |
| The public PIN rotates every time a tunnel starts | a QR that worked two minutes ago now says 瀵嗙爜閿欒 |
| Two tunnel managers | `闅ч亾杩涚▼閫€鍑?(code=4294967295)`, then every scan is **error 1033** |

The third one is the nastiest: nothing looks wrong 鈥?the panel shows an address,
the PIN file has a value, but the value changed underneath you.

The fourth one is self-inflicted: a second `cloudflared` (for example a script
that rebuilds the tunnel on a timer) kills the plugin's process, the panel keeps
displaying the now-dead hostname, and every scan returns 1033. **Let the plugin
own the tunnel.**

## Error cheat sheet

| Error | Meaning | Fix |
|---|---|---|
| **1033** | Cloudflare has no live tunnel for that hostname | The QR is stale or the process died. Scan the panel's current QR. |
| **530** | Tunnel registered but its data path is broken | A proxy/VPN is intercepting it. Turn off TUN mode, or add `*.argotunnel.com` and `*.trycloudflare.com` to its direct rules. |
| 瀵嗙爜閿欒 | PIN rotated, or LAN PIN used on a public URL | They are different PINs: `token` = public, `token-lan` = LAN. Pin both. |
| subresources 401 on LAN | Browser refused the cookie | Safari on `http://` + bare IP. Use the HTTPS public entry, or Chrome. |

## Company networks

Corporate networks usually break the outbound path a tunnel needs. Best fallback
needs no tunnel at all: **phone shares a 4G hotspot, computer joins it, then use
the LAN QR.** Same result, and no corporate firewall in the way.

## Scope

Windows. The scripts resolve pnpm and the DSH executable from the running
process, so they survive a different install location. `pocket-tunnel.ps1` is a
fallback for when the plugin's own tunnel cannot work: it runs an independent
cloudflared with `--protocol quic` (UDP, so it ignores HTTP proxies) and can
render a QR to a file 鈥?but disable the plugin's public access first, or they
will fight.

## License

MIT

