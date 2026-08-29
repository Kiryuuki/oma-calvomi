# OmaCalvomi — Calendar & Agenda for Omarchy Desktop

A month grid calendar and daily agenda flyout for Omarchy Desktop with deep **Yuvomi** synchronization, recurring events, birthday tracking, and desktop meeting alerts.

> [!IMPORTANT]
> **Yuvomi Required**: This plugin synchronizes with a self-hosted [Yuvomi](https://github.com/Yuvomi/yuvomi) instance (v2.50+). You will need your Yuvomi server URL and an API Bearer token.

---

## 🌟 Features

- **📅 Month Grid & ISO Weeks**:
  - Full-month grid with ISO week numbers.
  - Multi-colored event dots per day.
  - Year and life progress gauges.
- **✨ Quick Event & Birthday Creator (`+` / `n`)**:
  - Direct event creation with start/end time, all-day toggle, location/video links, and color picker.
  - **Repeat / Recurrence rules** (`Daily`, `Weekly`, `Monthly`, `Yearly`, `Mon-Fri`).
  - **Dedicated Birthday Creator**: Calculates age, adds cake icon (`󰎤`) and custom reminder lead time.
- **🔔 Desktop Meeting Alerts**:
  - Dispatches standard desktop notifications (`notify-send`) 5–15 minutes before meetings start, complete with video join links (Google Meet, Zoom, MS Teams).
- **⚙️ In-Panel Settings**:
  - Configure Server URL and API Key directly in the UI.
  - 1-click live connection tester and instant sync.

---

## ⌨️ Keyboard Shortcuts

| Key | Action |
|---|---|
| `n` / `+` | Open **Quick Event / Birthday Creator** |
| `t` | Jump to **Today** |
| `[` / `]` | Previous / Next Month |
| `{` / `}` | Previous / Next Year |
| `r` | Refresh & Re-sync |
| `Esc` | Close flyout |

---

## ⚙️ Configuration

Configure via the in-panel settings tab (`󰒓`), or manually in `~/.config/omarchy/yuvomi-sync.json`:
```json
{
  "baseUrl": "http://192.168.100.108:8443",
  "apiKey": "YOUR_YUVOMI_API_KEY",
  "window": {
    "pastDays": 14,
    "futureDays": 90
  }
}
```

---

## 📄 License & Attribution

- Licensed under MIT.
- Built for Omarchy Quattro Desktop.
- Original calendar base cloned and enhanced from `tmn73.calendar`.
