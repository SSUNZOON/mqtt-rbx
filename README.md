# mqtt-rbx

A Claude Code / agent skill for running your **own authenticated Mosquitto
broker** locally — as an alternative to a shared/anonymous classroom broker —
and controlling XIAO ESP32C6 boards over it under the `RBX/` topic
namespace, plus a browser dashboard that shows which devices are online.

- Broker: your own machine (Windows service via Eclipse Mosquitto)
- Auth: username/password, no anonymous access
- Listeners: `1883` (plain MQTT, boards) and `9001` (MQTT over WebSockets, dashboard)
- Topics: `RBX/<device_id>/{led/set,led/state,sensor/a0,status}`
- Scale: a handful of accounts out of the box (default 4 device + 1 dashboard), easy to extend to ~10

## Install as a skill

```bash
npx skills add <owner>/mqtt-rbx
```

(See [skills.sh](https://skills.sh/) for the Skills CLI.)

## Contents

```
skills/mqtt-rbx/
  SKILL.md              # what an agent reads to use this
  skill.sh               # CLI: name/login/check/devices/watch/led/sensor/pub
  setup/
    install-broker.ps1   # one-time, run as Administrator: configures the broker
  web/
    dashboard.html        # open directly in a browser - device on/off status
```

Full usage is documented in `skills/mqtt-rbx/SKILL.md`.

## Quick start

```powershell
winget install --id EclipseFoundation.Mosquitto -e
cd skills/mqtt-rbx/setup
.\install-broker.ps1 -Devices 4      # run as Administrator
```

Credentials are generated fresh on your machine every time you run the
script and are **never** committed to this repo — they're printed once and
saved to `%LOCALAPPDATA%\mqtt-rbx\credentials.txt` locally.

```bash
cd ../..
./skill.sh name RBX_esp01
./skill.sh login RBX_esp01 <password from credentials.txt>
./skill.sh check
```

Open `skills/mqtt-rbx/web/dashboard.html?host=<broker LAN IP>` in a browser
for the online/offline dashboard.
