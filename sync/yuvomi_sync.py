#!/usr/bin/env python3
"""
Sync Yuvomi Calendar into Omarchy Calendar State file.
Also supports CLI connection testing, event creation, birthday creation, recurrence, and desktop alert checking.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

CONTRACT_VERSION = 1
CONTRACT_PATH = Path.home() / ".local" / "state" / "omarchy" / "calendar-events.json"
DEFAULT_CONFIG_PATH = Path.home() / ".config" / "omarchy" / "yuvomi-sync.json"
ALERTS_STATE_PATH = Path.home() / ".local" / "state" / "omarchy" / "calendar-notified.json"

MEETING_URL_RE = re.compile(
    r"https://(?:[a-zA-Z0-9-]+\.)?(?:zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com|meet\.jit\.si)/[^\s\"'<>]+"
)
COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def resolve_local_tz():
    tz_val = os.environ.get("TZ")
    if tz_val:
        try:
            return ZoneInfo(tz_val.lstrip(":"))
        except (ZoneInfoNotFoundError, ValueError):
            pass
    if os.path.islink("/etc/localtime"):
        try:
            target = os.readlink("/etc/localtime")
            parts = Path(target).parts
            if "zoneinfo" in parts:
                name = "/".join(parts[parts.index("zoneinfo") + 1 :])
                if name:
                    return ZoneInfo(name)
        except Exception:
            pass
    return datetime.now().astimezone().tzinfo


def load_config(config_path=DEFAULT_CONFIG_PATH):
    path = Path(config_path)
    if not path.exists():
        return {
            "baseUrl": "http://dokploy.tail9fd122.ts.net:8443",
            "apiKey": "",
            "window": {"pastDays": 14, "futureDays": 90},
        }
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_config(cfg, config_path=DEFAULT_CONFIG_PATH):
    path = Path(config_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(path, cfg)


def api_request(base_url, endpoint, api_key, method="GET", body=None, params=None, timeout=12):
    url = urllib.parse.urljoin(base_url.rstrip("/") + "/", endpoint.lstrip("/"))
    if params:
        url += "?" + urllib.parse.urlencode(params)

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "User-Agent": "omarchy-yuvomi-sync/2.0",
    }

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, headers=headers, data=data, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        raw = resp.read().decode(charset, errors="ignore")
        return json.loads(raw) if raw.strip() else {}


def parse_datetime(val_str, local_tz):
    if not val_str:
        return None, False
    val = val_str.strip()
    if not val:
        return None, False

    # YYYY-MM-DD
    if len(val) == 10 and val.count("-") == 2:
        try:
            parts = [int(p) for p in val.split("-")]
            return datetime(parts[0], parts[1], parts[2], 0, 0, 0, tzinfo=local_tz), True
        except Exception:
            return None, False

    # Handle ISO formats
    val_clean = val.replace(" ", "T")
    if val_clean.endswith("Z"):
        try:
            dt = datetime.fromisoformat(val_clean[:-1]).replace(tzinfo=timezone.utc)
            return dt.astimezone(local_tz), False
        except Exception:
            return None, False

    try:
        dt = datetime.fromisoformat(val_clean)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=local_tz)
        else:
            dt = dt.astimezone(local_tz)
        return dt, False
    except Exception:
        return None, False


def find_meeting_url(text):
    if not text:
        return ""
    match = MEETING_URL_RE.search(text)
    return match.group(0) if match else ""


def normalize_color(color_str, fallback="#3B82F6"):
    if isinstance(color_str, str) and COLOR_RE.match(color_str):
        return color_str
    return fallback


def write_atomic(path, doc):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_name = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(doc, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def test_connection(base_url, api_key):
    try:
        base_url = base_url.rstrip("/")
        ver_res = api_request(base_url, "/api/v1/version", api_key, timeout=5)
        cal_res = api_request(base_url, "/api/v1/calendar?from=2026-01-01&to=2026-12-31", api_key, timeout=6)
        count = len(cal_res.get("data", [])) if isinstance(cal_res, dict) else 0
        ver = ver_res.get("data", {}).get("version", "2.50.3") if isinstance(ver_res, dict) else "OK"
        return {"ok": True, "version": ver, "eventCount": count, "error": None}
    except Exception as e:
        return {"ok": False, "version": None, "eventCount": 0, "error": str(e)}


def create_event(title, start_iso, end_iso=None, all_day=False, location="", description="", color="#3B82F6", recurrence=None, config_path=DEFAULT_CONFIG_PATH):
    cfg = load_config(config_path)
    base_url = cfg["baseUrl"].rstrip("/")
    api_key = cfg["apiKey"]

    body = {
        "title": title.strip(),
        "start_datetime": start_iso,
        "end_datetime": end_iso if end_iso else None,
        "all_day": 1 if all_day else 0,
        "location": location.strip() if location else None,
        "description": description.strip() if description else None,
        "color": color if color else None,
        "recurrence_rule": recurrence.strip() if recurrence else None,
    }

    try:
        res = api_request(base_url, "/api/v1/calendar", api_key, method="POST", body=body)
        sync(config_path)
        return {"ok": True, "data": res.get("data"), "error": None}
    except Exception as e:
        return {"ok": False, "data": None, "error": str(e)}


def create_birthday(name, birth_date, notes="", reminder_offset=None, config_path=DEFAULT_CONFIG_PATH):
    cfg = load_config(config_path)
    base_url = cfg["baseUrl"].rstrip("/")
    api_key = cfg["apiKey"]

    body = {
        "name": name.strip(),
        "birth_date": birth_date.strip(),
        "notes": notes.strip() if notes else None,
        "reminder_offset": str(reminder_offset) if reminder_offset else None,
    }

    try:
        res = api_request(base_url, "/api/v1/birthdays", api_key, method="POST", body=body)
        sync(config_path)
        return {"ok": True, "data": res.get("data"), "error": None}
    except Exception as e:
        return {"ok": False, "data": None, "error": str(e)}


def check_and_notify_alerts(lead_minutes=15):
    """Sends desktop notification alerts for upcoming meetings and events."""
    if not CONTRACT_PATH.exists():
        return

    with open(CONTRACT_PATH, "r", encoding="utf-8") as f:
        doc = json.load(f)

    events = doc.get("occurrences", [])
    now = datetime.now().astimezone()
    lead_delta = timedelta(minutes=lead_minutes)

    notified = {}
    if ALERTS_STATE_PATH.exists():
        try:
            with open(ALERTS_STATE_PATH, "r", encoding="utf-8") as f:
                notified = json.load(f)
        except Exception:
            notified = {}

    cutoff = (now - timedelta(days=1)).isoformat()
    notified = {k: v for k, v in notified.items() if v >= cutoff}

    for ev in events:
        ev_id = ev.get("id")
        if not ev_id or ev_id in notified:
            continue

        if ev.get("allDay"):
            continue

        start_str = ev.get("start")
        if not start_str:
            continue

        try:
            start_dt = datetime.fromisoformat(start_str.replace("Z", "+00:00"))
            if start_dt.tzinfo is None:
                start_dt = start_dt.replace(tzinfo=now.tzinfo)
        except Exception:
            continue

        diff = start_dt - now
        if timedelta(seconds=0) <= diff <= lead_delta:
            title = ev.get("title", "Upcoming Event")
            cal_name = ev.get("calendarName", "Calendar")
            mins_left = max(1, int(round(diff.total_seconds() / 60)))
            meeting_url = ev.get("meetingUrl", "")

            body_msg = f"{mins_left}m away ({start_dt.strftime('%H:%M')}) · {cal_name}"
            if meeting_url:
                body_msg += f"\nVideo link: {meeting_url}"

            cmd = [
                "notify-send",
                "-a", "Omarchy Calendar",
                "-i", "appointment-soon",
                "-u", "normal",
                title,
                body_msg,
            ]
            try:
                subprocess.run(cmd, check=False)
                notified[ev_id] = now.isoformat()
            except Exception as e:
                print(f"Failed to send notification: {e}", file=sys.stderr)

    write_atomic(ALERTS_STATE_PATH, notified)


def sync(config_path=DEFAULT_CONFIG_PATH, out_path=CONTRACT_PATH):
    cfg = load_config(config_path)
    base_url = cfg.get("baseUrl", "").rstrip("/")
    api_key = cfg.get("apiKey", "")
    past_days = cfg.get("window", {}).get("pastDays", 14)
    future_days = cfg.get("window", {}).get("futureDays", 90)

    if not base_url or not api_key:
        print("Yuvomi baseUrl or apiKey not configured. Skipping sync.", file=sys.stderr)
        return

    local_tz = resolve_local_tz()
    today = datetime.now(local_tz).date()
    from_date = today - timedelta(days=past_days)
    to_date = today + timedelta(days=future_days)

    # 1. Fetch Users / Members
    users_map = {}
    try:
        members_res = api_request(base_url, "/api/v1/family/members", api_key)
        for u in members_res.get("data", []):
            users_map[u["id"]] = u
    except Exception as e:
        print(f"Warning: Could not fetch family members: {e}", file=sys.stderr)

    # 2. Fetch Subscriptions
    subs_map = {}
    try:
        subs_res = api_request(base_url, "/api/v1/calendar/subscriptions", api_key)
        for s in subs_res.get("data", []):
            subs_map[s["id"]] = s
    except Exception as e:
        print(f"Warning: Could not fetch subscriptions: {e}", file=sys.stderr)

    # 3. Fetch Calendar Events
    events_res = api_request(
        base_url,
        "/api/v1/calendar",
        api_key,
        params={"from": from_date.isoformat(), "to": to_date.isoformat()},
    )
    raw_events = events_res.get("data", [])

    normalized_rows = []

    for ev in raw_events:
        ev_id = str(ev.get("id"))
        title = ev.get("title") or "Untitled Event"
        desc = ev.get("description") or ""
        location = ev.get("location") or ""
        all_day_raw = bool(ev.get("all_day"))

        is_birthday = (
            bool(ev.get("birthday_name"))
            or ev.get("icon") == "cake"
            or title.startswith("Birthday:")
            or "birthday" in title.lower()
        )

        sub_id = ev.get("subscription_id")
        cal_name_raw = ev.get("cal_name")
        ext_source = ev.get("external_source")

        if is_birthday:
            cal_id = "yuvomi:birthdays"
            cal_name = "Birthdays & Anniversaries"
            cal_color = normalize_color(ev.get("color"), "#E11D48")
        elif sub_id and sub_id in subs_map:
            sub = subs_map[sub_id]
            cal_id = f"yuvomi:sub:{sub_id}"
            cal_name = sub.get("name") or "Subscription"
            cal_color = normalize_color(sub.get("color") or ev.get("color"), "#10B981")
        elif cal_name_raw or (ext_source and ext_source != "local"):
            name = cal_name_raw or ext_source.capitalize()
            cal_id = f"yuvomi:ext:{ev.get('external_calendar_id') or name.lower()}"
            cal_name = name
            cal_color = normalize_color(ev.get("cal_color") or ev.get("color"), "#8B5CF6")
        elif ev.get("assigned_users") and len(ev["assigned_users"]) == 1:
            u = ev["assigned_users"][0]
            cal_id = f"yuvomi:user:{u['id']}"
            cal_name = u.get("display_name") or u.get("username") or f"User {u['id']}"
            cal_color = normalize_color(u.get("avatar_color") or ev.get("color"), "#3B82F6")
        else:
            cal_id = "yuvomi:family"
            cal_name = "Family"
            cal_color = normalize_color(ev.get("color"), "#3B82F6")

        start_dt, start_is_date = parse_datetime(ev.get("start_datetime"), local_tz)
        end_dt, end_is_date = parse_datetime(ev.get("end_datetime"), local_tz)

        if not start_dt:
            continue

        is_all_day = all_day_raw or start_is_date
        meeting_url = find_meeting_url(desc) or find_meeting_url(location)

        if is_all_day:
            start_date = start_dt.date()
            if end_dt:
                end_date = end_dt.date()
                if end_date < start_date:
                    end_date = start_date
            else:
                end_date = start_date

            curr = start_date
            while curr <= end_date:
                d_key = curr.isoformat()
                row = {
                    "id": f"{ev_id}:{d_key}",
                    "calendarId": cal_id,
                    "calendarName": cal_name,
                    "color": cal_color,
                    "dateKey": d_key,
                    "start": f"{d_key}T00:00:00",
                    "end": f"{d_key}T23:59:59",
                    "allDay": True,
                    "title": title,
                    "location": location,
                    "description": desc,
                    "isBirthday": is_birthday,
                    "recurrence": ev.get("recurrence_rule"),
                }
                if meeting_url:
                    row["meetingUrl"] = meeting_url
                normalized_rows.append(row)
                curr += timedelta(days=1)
        else:
            if not end_dt or end_dt < start_dt:
                end_dt = start_dt + timedelta(hours=1)

            curr_date = start_dt.date()
            end_date = end_dt.date()

            while curr_date <= end_date:
                d_key = curr_date.isoformat()
                row = {
                    "id": f"{ev_id}:{d_key}",
                    "calendarId": cal_id,
                    "calendarName": cal_name,
                    "color": cal_color,
                    "dateKey": d_key,
                    "start": start_dt.isoformat(),
                    "end": end_dt.isoformat(),
                    "allDay": False,
                    "title": title,
                    "location": location,
                    "description": desc,
                    "isBirthday": is_birthday,
                    "recurrence": ev.get("recurrence_rule"),
                }
                if meeting_url:
                    row["meetingUrl"] = meeting_url
                normalized_rows.append(row)
                curr_date += timedelta(days=1)

    # 4. Extract distinct calendars for the filter UI
    cal_dict = {}
    for r in normalized_rows:
        cid = r["calendarId"]
        if cid not in cal_dict:
            cal_dict[cid] = {
                "id": cid,
                "name": r["calendarName"],
                "color": r["color"],
                "isBirthday": r.get("isBirthday", False),
            }

    calendars_list = list(cal_dict.values())

    contract_doc = {
        "version": CONTRACT_VERSION,
        "syncedAt": datetime.now(timezone.utc).isoformat(),
        "source": "yuvomi",
        "calendars": calendars_list,
        "occurrences": normalized_rows,
    }

    write_atomic(out_path, contract_doc)
    print(f"Successfully synced {len(normalized_rows)} occurrences from Yuvomi to {out_path}")
    check_and_notify_alerts()


def main():
    parser = argparse.ArgumentParser(description="Yuvomi Calendar Sync & Management")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH), help="Path to yuvomi-sync.json")
    parser.add_argument("--out", default=str(CONTRACT_PATH), help="Path to calendar-events.json")
    parser.add_argument("--test", action="store_true", help="Test connection to Yuvomi server")
    parser.add_argument("--url", default="", help="Yuvomi Base URL")
    parser.add_argument("--key", default="", help="Yuvomi API Key")
    parser.add_argument("--save-config", action="store_true", help="Save URL and key to config file")
    parser.add_argument("--create-event", action="store_true", help="Create a new calendar event")
    parser.add_argument("--create-birthday", action="store_true", help="Create a new birthday")
    parser.add_argument("--name", default="", help="Person / event name")
    parser.add_argument("--birth-date", default="", help="Birth date YYYY-MM-DD")
    parser.add_argument("--reminder-offset", default="1440", help="Reminder offset minutes")
    parser.add_argument("--title", default="", help="Event title")
    parser.add_argument("--start", default="", help="Start ISO datetime")
    parser.add_argument("--end", default="", help="End ISO datetime")
    parser.add_argument("--all-day", action="store_true", help="All day event")
    parser.add_argument("--recurrence", default="", help="RRULE string (e.g. FREQ=WEEKLY)")
    parser.add_argument("--location", default="", help="Event location or meeting link")
    parser.add_argument("--desc", default="", help="Event description")
    parser.add_argument("--color", default="#3B82F6", help="Event color hex")
    parser.add_argument("--check-alerts", action="store_true", help="Check and dispatch meeting alerts")
    args = parser.parse_args()

    if args.test:
        cfg = load_config(args.config)
        u = args.url.strip() or cfg.get("baseUrl", "")
        k = args.key.strip() or cfg.get("apiKey", "")
        res = test_connection(u, k)
        print(json.dumps(res))
    elif args.save_config:
        cfg = load_config(args.config)
        if args.url.strip():
            cfg["baseUrl"] = args.url.strip()
        if args.key.strip():
            cfg["apiKey"] = args.key.strip()
        save_config(cfg, args.config)
        sync(args.config, args.out)
        print(json.dumps({"ok": True, "message": "Saved config and synced"}))
    elif args.create_birthday:
        res = create_birthday(
            name=args.name or args.title,
            birth_date=args.birth_date or args.start[:10],
            notes=args.desc,
            reminder_offset=args.reminder_offset,
            config_path=args.config,
        )
        print(json.dumps(res))
    elif args.create_event:
        res = create_event(
            title=args.title,
            start_iso=args.start,
            end_iso=args.end,
            all_day=args.all_day,
            location=args.location,
            description=args.desc,
            color=args.color,
            recurrence=args.recurrence,
            config_path=args.config,
        )
        print(json.dumps(res))
    elif args.check_alerts:
        check_and_notify_alerts()
    else:
        sync(args.config, args.out)


if __name__ == "__main__":
    main()
