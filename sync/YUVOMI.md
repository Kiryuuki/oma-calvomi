# Yuvomi Calendar Integration for Omarchy Calendar

This module continuously syncs calendar events from your **Yuvomi** instance (or any compatible CalDAV/JSON backend) directly into the Omarchy Calendar widget.

---

## Architecture

- **Sync Script**: `yuvomi_sync.py`
  - Fetches calendar events, recurring schedules, and meetings from your Yuvomi server.
  - Automatically calculates time boundaries (`pastDays: 7`, `futureDays: 60`).
  - Formats events into the native Omarchy Calendar JSON format:
    - ISO timestamps with timezone resolution
    - Video call link extraction (`Google Meet`, `Zoom`, `Teams`, `Jitsi`) enabling the **1-Click Join** button.
    - Color tagging per calendar.
  - Atomically writes to `~/.local/state/omarchy/calendar-events.json`.
- **Systemd Timer**: `omarchy-yuvomi-sync.{service,timer}`
  - Runs automatically every 5 minutes in the background without UI blocking.

---

## Configuration

Configuration is stored in `~/.config/omarchy/yuvomi-sync.json`:

```json
{
  "yuvomiUrl": "https://calendar.yuvomi.com",
  "apiKey": "YOUR_YUVOMI_API_KEY",
  "calendars": {
    "include": [],
    "exclude": []
  },
  "window": {
    "pastDays": 7,
    "futureDays": 60
  }
}
```

---

## Systemd Service & Timer Management

To check sync status or view logs:
```bash
# View live sync logs
journalctl --user -u omarchy-yuvomi-sync -f

# Check timer schedule
systemctl --user list-timers omarchy-yuvomi-sync.timer

# Run a manual sync immediately
python3 ~/.config/omarchy/plugins/tmn73.calendar/sync/yuvomi_sync.py
```
