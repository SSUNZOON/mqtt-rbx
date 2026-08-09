---
name: mqtt-rbx
description: Run your own authenticated Mosquitto broker locally (RBX/ topic namespace) and control/watch XIAO ESP32C6 boards over it. Use when the user wants a private broker instead of the classroom one, needs username/password auth, wants MQTT over WebSockets on 9001, or wants a device online/offline dashboard.
---

# mqtt-rbx

A private, authenticated Mosquitto broker you run on your own machine — no
shared classroom broker, no anonymous access. Up to ~10 clients, topic
namespace `RBX/`. Built for XIAO ESP32C6 boards but works with anything that
speaks MQTT.

This is the same shape as `mqtt-classroom`, with three differences: it's
**your** broker (runs on your PC), it requires **username/password auth**,
and it also serves **MQTT over WebSockets on 9001** so a browser dashboard
can connect directly.

## One-time setup

1. Install Mosquitto (Windows): `winget install --id EclipseFoundation.Mosquitto -e`
   (installs the broker as a Windows service, plus `mosquitto_pub` / `mosquitto_sub`
   / `mosquitto_passwd` — add `C:\Program Files\mosquitto` to PATH if the skill
   scripts don't find them automatically).
2. Run the setup script **as Administrator** (it edits the service's config and
   restarts it):
   ```powershell
   cd setup
   .\install-broker.ps1 -Devices 4 -DashboardUser
   ```
   This generates a fresh random password for each account (`RBX_esp01`..`RBX_esp0N`
   plus `RBX_dashboard`), writes `mosquitto.conf` with two listeners —
   `1883` (plain MQTT, for boards) and `9001` (MQTT over WebSockets, for the
   dashboard) — sets `allow_anonymous false`, writes a password file and an
   ACL file (each device can only read/write its own `RBX/<id>/#` subtree;
   the dashboard account is read-only across `RBX/#`), and restarts the
   `mosquitto` service.
   **The generated credentials are never written into this repo.** They're
   printed once to the console and saved to
   `%LOCALAPPDATA%\mqtt-rbx\credentials.txt` on the machine you ran the
   script on — copy what you need from there into each board's
   `arduino_secrets.h` and keep that file out of git.
3. Note the broker machine's LAN IP the script prints (or run
   `ipconfig` / `Get-NetIPAddress`) — boards and the dashboard both need it.

## Your device name

```bash
./skill.sh name RBX_esp01     # save (once)
./skill.sh name                # show what is saved
```

Stored in `~/.mqtt-rbx`. `MQTT_DEVICE` in the environment overrides it for
one shell. The name must match `DEVICE_NAME` in the board's
`arduino_secrets.h` — same rule as mqtt-classroom, since it decides the
board's topic prefix.

## Credentials for the CLI

```bash
export MQTT_HOST=192.168.0.32          # the broker machine's LAN IP
export MQTT_USER=RBX_esp01
export MQTT_PASS=<from credentials.txt>
```

Or save them once: `./skill.sh login RBX_esp01 <password>` (writes to
`~/.mqtt-rbx`, same file as `name`).

## Topics

| Topic | Direction | Payload |
|---|---|---|
| `RBX/<id>/led/set` | you → board | `on`, `off`, `toggle` |
| `RBX/<id>/led/state` | board → you | `on`, `off` (retained) |
| `RBX/<id>/sensor/a0` | board → you | `{"raw":2048,"mv":1650}` every 2s |
| `RBX/<id>/status` | board → you | `online`, `offline` (retained, last will) |

`status` and `led/state` are retained, so a fresh subscriber (including the
dashboard) learns current state immediately instead of waiting for the next
change.

## Usage

```bash
./skill.sh name RBX_esp01        # save your board's name (once)
./skill.sh login RBX_esp01 ****  # save credentials (once)
./skill.sh check                 # is the broker reachable at all?
./skill.sh devices                # which boards are online right now
./skill.sh led on                 # your board's LED on
./skill.sh led off
./skill.sh led RBX_esp02 on       # or name another board explicitly
./skill.sh sensor                 # stream your board's A0 readings
./skill.sh watch                  # every message from your board
```

## Firmware (XIAO ESP32C6)

Point the board at this broker instead of the classroom one:

```cpp
#define WIFI_SSID     "..."
#define WIFI_PASSWORD "..."
#define MQTT_HOST     "192.168.0.32"   // this machine's LAN IP
#define MQTT_PORT     1883
#define MQTT_USER     "RBX_esp01"
#define MQTT_PASS     "..."             // from credentials.txt
#define DEVICE_NAME   "RBX_esp01"
```

`PubSubClient::connect()` takes a username/password overload:

```cpp
mqtt.connect(DEVICE_NAME, MQTT_USER, MQTT_PASS,
             topicStatus.c_str(), 0, true, "offline");
```

## Dashboard

`web/dashboard.html` shows every `RBX/*` device as online/offline (from the
retained `status` topic), with last-seen time. Open it directly in a browser
— no server needed. It connects over WebSockets (`ws://<host>:9001`), so it
asks for the broker host and the `RBX_dashboard` username/password on first
load and remembers them in `localStorage`.

```
dashboard.html?host=192.168.0.32
```

A browser cannot open a raw MQTT TCP socket, which is why the dashboard
needs the 9001 listener rather than 1883.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `check` fails, connection refused | Broker service not running — `Get-Service mosquitto`, or `install-broker.ps1` wasn't run as Administrator |
| Board connects to WiFi but never reaches MQTT | Wrong `MQTT_HOST` (must be the broker PC's LAN IP, not `192.168.0.49`/classroom), or wrong username/password |
| `Connection Refused: not authorised` (rc=5) | Bad username/password, or the account isn't in the password file — rerun `install-broker.ps1` |
| Dashboard can't connect | Using `ws://` not `wss://`, wrong port (must be 9001, not 1883), or Windows Firewall blocking 9001 on this PC — allow both 1883 and 9001 for `mosquitto.exe` |
| `mosquitto_sub not found` | Install the clients; `skill.sh` already looks in the default Windows install path |
| Two boards fighting, kicking each other offline | They share the same `DEVICE_NAME` — every id must be unique |
