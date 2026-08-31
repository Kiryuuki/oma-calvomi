#!/usr/bin/env python3
"""
Yuvomi Calendar Sync & Holiday Management Engine for Omarchy Desktop.
Provides secure synchronization, country holiday detection and ingestion,
event creation, birthday tracking, and desktop alerts with descriptor safety.
"""

import argparse
from datetime import datetime, date, timedelta
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "omarchy" / "yuvomi-sync.json"
CONTRACT_PATH = Path.home() / ".local" / "state" / "omarchy" / "calendar-events.json"
ALERT_STATE_PATH = Path.home() / ".local" / "state" / "omarchy" / "yuvomi-alerts-state.json"
CACHE_DIR = Path.home() / ".local" / "state" / "omarchy"

MAX_STATE_BYTES = 512 * 1024  # 512 KB ceiling


def get_local_timezone():
    if ZoneInfo:
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


def detect_system_country():
    """Detects country code (ISO-3166-1 alpha-2) and friendly name from timezone or locale."""
    tz_country_map = {
        "Manila": ("PH", "Philippines"),
        "Tokyo": ("JP", "Japan"),
        "Singapore": ("SG", "Singapore"),
        "Seoul": ("KR", "South Korea"),
        "Hong_Kong": ("HK", "Hong Kong"),
        "Taipei": ("TW", "Taiwan"),
        "Bangkok": ("TH", "Thailand"),
        "Jakarta": ("ID", "Indonesia"),
        "Kuala_Lumpur": ("MY", "Malaysia"),
        "London": ("GB", "United Kingdom"),
        "Paris": ("FR", "France"),
        "Berlin": ("DE", "Germany"),
        "New_York": ("US", "United States"),
        "Chicago": ("US", "United States"),
        "Los_Angeles": ("US", "United States"),
        "Toronto": ("CA", "Canada"),
        "Sydney": ("AU", "Australia"),
    }
    try:
        target = os.readlink("/etc/localtime")
        for tz_city, (cc, cname) in tz_country_map.items():
            if tz_city in target:
                return cc, cname
    except Exception:
        pass

    loc = os.environ.get("LANG", "") or os.environ.get("LC_TIME", "")
    if "_" in loc:
        raw_cc = loc.split("_")[1].split(".")[0].upper()
        if len(raw_cc) == 2:
            return raw_cc, raw_cc

    return "PH", "Philippines"


def fetch_country_holidays(country_code, year):
    """Fetches public holidays from Nager.Date API with local file caching."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_file = CACHE_DIR / f"holidays-{country_code}-{year}.json"

    if cache_file.exists():
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list) and len(data) > 0:
                    return data
        except Exception:
            pass

    url = f"https://date.nager.at/api/v3/PublicHolidays/{year}/{country_code}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "omarchy-calvomi/1.0"})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if isinstance(data, list):
                write_atomic(cache_file, data)
                return data
    except Exception as e:
        print(f"Holidays API fetch note: {e}", file=sys.stderr)

    return []


def load_config(config_path=DEFAULT_CONFIG_PATH):
    path = Path(config_path)
    if not path.exists():
        return {
            "baseUrl": "",
            "apiKey": "",
            "window": {"pastDays": 14, "futureDays": 90},
            "includeHolidays": True,
        }
    try:
        st = path.stat()
        if st.st_uid != os.getuid() or not stat.S_ISREG(st.st_mode):
            return {"baseUrl": "", "apiKey": "", "window": {"pastDays": 14, "futureDays": 90}, "includeHolidays": True}
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {"baseUrl": "", "apiKey": "", "window": {"pastDays": 14, "futureDays": 90}, "includeHolidays": True}


def write_atomic(path, data):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    raw_bytes = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(raw_bytes) > MAX_STATE_BYTES:
        print(f"Error: Payload size {len(raw_bytes)} exceeds ceiling {MAX_STATE_BYTES}", file=sys.stderr)
        return

    handle, temp_name = tempfile.mkstemp(dir=str(p.parent), suffix=".tmp")
    try:
        os.fchmod(handle, 0o600)
        with os.fdopen(handle, "wb") as stream:
            stream.write(raw_bytes)
            stream.flush()
            os.fsync(stream.fileno())
        if p.exists():
            st = p.lstat()
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
                p.unlink(missing_ok=True)
        os.replace(temp_name, p)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def validate_url(url: str) -> str:
    url = (url or "").strip()
    if not url:
        raise ValueError("URL cannot be empty")
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("https", "http"):
        raise ValueError(f"Invalid URL scheme: {parsed.scheme}. Must be https:// or http://")
    if not parsed.netloc:
        raise ValueError("Invalid URL host")
    return url


def api_request(base_url, endpoint, api_key, method="GET", body=None, params=None, timeout=12):
    valid_base = validate_url(base_url)
    url = urllib.parse.urljoin(valid_base.rstrip("/") + "/", endpoint.lstrip("/"))
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


def sanitize_text(text: str, max_len: int = 500) -> str:
    if not text:
        return ""
    clean = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', str(text)).strip()
    return clean[:max_len]


def test_connection(base_url, api_key):
    if not base_url or not api_key:
        return {"ok": False, "error": "Base URL and API Key are required."}
    try:
        data = api_request(base_url, "/api/v1/auth/me", api_key, timeout=8)
        user = data.get("user", {})
        username = sanitize_text(user.get("username") or user.get("name") or "Authenticated")
        return {"ok": True, "user": username}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"HTTP {e.code}: {e.reason}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def create_birthday(name, birth_date, notes="", reminder_offset="1440", config_path=DEFAULT_CONFIG_PATH):
    cfg = load_config(config_path)
    base_url = cfg.get("baseUrl")
    api_key = cfg.get("apiKey")
    if not base_url or not api_key:
        return {"ok": False, "error": "Yuvomi not configured."}

    payload = {
        "name": sanitize_text(name, 200),
        "birthDate": str(birth_date).strip(),
        "notes": sanitize_text(notes, 1000),
        "reminderOffset": int(reminder_offset) if str(reminder_offset).isdigit() else 1440,
    }
    try:
        res = api_request(base_url, "/api/v1/birthdays", api_key, method="POST", body=payload)
        sync(config_path)
        return {"ok": True, "data": res}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def create_event(title, start_iso, end_iso, all_day=False, location="", description="", color="#3B82F6", recurrence="", config_path=DEFAULT_CONFIG_PATH):
    cfg = load_config(config_path)
    base_url = cfg.get("baseUrl")
    api_key = cfg.get("apiKey")
    if not base_url or not api_key:
        return {"ok": False, "error": "Yuvomi not configured."}

    payload = {
        "title": sanitize_text(title, 200),
        "start_datetime": str(start_iso).strip(),
        "end_datetime": str(end_iso).strip(),
        "all_day": 1 if all_day else 0,
        "location": sanitize_text(location, 300),
        "description": sanitize_text(description, 2000),
        "color": sanitize_text(color, 20) or "#3B82F6",
    }
    if recurrence:
        payload["recurrence_rule"] = sanitize_text(recurrence, 100)

    try:
        res = api_request(base_url, "/api/v1/calendar", api_key, method="POST", body=payload)
        sync(config_path)
        return {"ok": True, "data": res}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def sync(config_path=DEFAULT_CONFIG_PATH, out_path=CONTRACT_PATH, sync_holidays_to_server=False):
    cfg = load_config(config_path)
    base_url = cfg.get("baseUrl")
    api_key = cfg.get("apiKey")
    include_holidays = cfg.get("includeHolidays", True)

    now = datetime.now()
    start_dt = (now - timedelta(days=30)).strftime("%Y-%m-%d")
    end_dt = (now + timedelta(days=120)).strftime("%Y-%m-%d")

    events_data = []
    if base_url and api_key:
        try:
            res = api_request(base_url, "/api/v1/calendar", api_key, params={"from": start_dt, "to": end_dt})
            if isinstance(res, dict):
                events_data = res.get("data") or res.get("events") or []
            elif isinstance(res, list):
                events_data = res
        except Exception as e:
            print(f"Calendar events fetch note: {e}", file=sys.stderr)

    normalized = []
    yuvomi_titles = set()

    for ev in events_data:
        t = sanitize_text(ev.get("title") or "Untitled", 200)
        s = str(ev.get("start_datetime") or ev.get("start") or "").strip()
        e = str(ev.get("end_datetime") or ev.get("end") or s).strip()
        loc = sanitize_text(ev.get("location") or "", 300)
        desc = sanitize_text(ev.get("description") or "", 2000)
        col = sanitize_text(ev.get("color") or "#3B82F6", 20)
        all_day = bool(ev.get("all_day") or ev.get("allDay", False))
        is_bday = bool(ev.get("icon") == "cake" or ev.get("birthday_name"))
        rrule = sanitize_text(ev.get("recurrence_rule") or ev.get("recurrence") or "", 100)

        if s:
            date_k = s[:10]
            yuvomi_titles.add((t.lower(), date_k))
            normalized.append({
                "id": str(ev.get("id") or f"ev-{len(normalized)}"),
                "title": t,
                "start": s,
                "end": e,
                "dateKey": date_k,
                "allDay": all_day,
                "isBirthday": is_bday,
                "location": loc,
                "description": desc,
                "color": col,
                "recurrence": rrule,
                "calendarId": "birthdays" if is_bday else "yuvomi",
                "calendarName": "Birthdays" if is_bday else "Yuvomi",
                "source": "yuvomi",
            })

    # Country Holidays Integration
    cc, cname = detect_system_country()
    if include_holidays:
        current_year = now.year
        for yr in (current_year, current_year + 1):
            h_list = fetch_country_holidays(cc, yr)
            for h in h_list:
                h_date = h.get("date")
                h_name = h.get("name") or "Public Holiday"
                h_local = h.get("localName") or ""
                disp_title = f"{h_name} ({h_local})" if h_local and h_local.lower() != h_name.lower() else h_name

                if h_date:
                    normalized.append({
                        "id": f"holiday-{cc}-{h_date}-{h_name}",
                        "title": disp_title,
                        "start": h_date,
                        "end": h_date,
                        "dateKey": h_date,
                        "allDay": True,
                        "isBirthday": False,
                        "isHoliday": True,
                        "location": cname,
                        "description": f"Official Public Holiday in {cname}",
                        "color": "#F59E0B",  # Gold / Amber for official holidays
                        "recurrence": "",
                        "calendarId": "holidays",
                        "calendarName": f"Holidays ({cc})",
                        "source": "country-holidays",
                    })

                    # If sync-to-server requested and not in Yuvomi yet
                    if sync_holidays_to_server and base_url and api_key:
                        if (disp_title.lower(), h_date) not in yuvomi_titles and (h_name.lower(), h_date) not in yuvomi_titles:
                            try:
                                api_request(base_url, "/api/v1/calendar", api_key, method="POST", body={
                                    "title": disp_title,
                                    "start_datetime": h_date,
                                    "end_datetime": h_date,
                                    "all_day": 1,
                                    "color": "#F59E0B",
                                    "location": cname,
                                    "description": f"National Public Holiday ({cname})",
                                })
                                print(f"Added holiday to Yuvomi: {disp_title} on {h_date}")
                            except Exception:
                                pass

    doc = {
        "version": 1,
        "updatedAt": datetime.now().astimezone().isoformat(),
        "timeZone": str(get_local_timezone()),
        "country": cc,
        "countryName": cname,
        "events": normalized,
    }
    write_atomic(out_path, doc)
    print(f"Synced {len(normalized)} events (including {cc} holidays) to {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Yuvomi Calendar Sync Engine")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG_PATH), help="Config file path")
    parser.add_argument("--out", default=str(CONTRACT_PATH), help="Output state path")
    parser.add_argument("--save-config", action="store_true", help="Save config JSON passed via stdin with 0600 permissions")
    parser.add_argument("--test", action="store_true", help="Test connection")
    parser.add_argument("--create-event", action="store_true", help="Create calendar event")
    parser.add_argument("--create-birthday", action="store_true", help="Create birthday")
    parser.add_argument("--sync-holidays", action="store_true", help="Push country holidays to Yuvomi")
    parser.add_argument("--title", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--birth-date", default="")
    parser.add_argument("--reminder-offset", default="1440")
    parser.add_argument("--start", default="")
    parser.add_argument("--end", default="")
    parser.add_argument("--all-day", action="store_true")
    parser.add_argument("--location", default="")
    parser.add_argument("--desc", default="")
    parser.add_argument("--color", default="#3B82F6")
    parser.add_argument("--recurrence", default="")
    parser.add_argument("--check-alerts", action="store_true")
    args = parser.parse_args()

    if args.save_config:
        raw_stdin = sys.stdin.read().strip() if not sys.stdin.isatty() else ""
        if raw_stdin:
            try:
                cfg_data = json.loads(raw_stdin)
                if isinstance(cfg_data, dict):
                    write_atomic(args.config, cfg_data)
                    print(json.dumps({"ok": True}))
                    sys.exit(0)
            except Exception as e:
                print(json.dumps({"ok": False, "error": str(e)}))
                sys.exit(1)
        print(json.dumps({"ok": False, "error": "No config payload provided on stdin"}))
        sys.exit(1)
    elif args.test:
        raw_stdin = sys.stdin.read().strip() if not sys.stdin.isatty() else ""
        if raw_stdin:
            try:
                cfg = json.loads(raw_stdin)
            except Exception:
                cfg = {}
        else:
            cfg = load_config(args.config)
        u = cfg.get("baseUrl", "")
        k = cfg.get("apiKey", "")
        res = test_connection(u, k)
        print(json.dumps(res))
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
    else:
        sync(args.config, args.out, sync_holidays_to_server=args.sync_holidays)


if __name__ == "__main__":
    main()
