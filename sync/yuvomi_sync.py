#!/usr/bin/env python3
"""
Yuvomi Calendar Sync & Holiday Management Engine for Omarchy Desktop.
Provides secure synchronization, country holiday detection and ingestion,
event creation, birthday tracking, and desktop alerts with descriptor safety.
"""

import argparse
from datetime import datetime, date, timedelta
import ipaddress
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
MAX_RESPONSE_BYTES = 512 * 1024  # 512 KB ceiling for remote HTTP responses


def is_loopback(host: str) -> bool:
    """Checks if a hostname or IP string represents a loopback address."""
    if not host:
        return False
    h = host.strip().lower()
    if h.startswith("[") and h.endswith("]"):
        h = h[1:-1]
    elif ":" in h and h.count(":") == 1:
        h = h.split(":", 1)[0]

    if h in ("localhost", "localhost.localdomain"):
        return True
    try:
        ip = ipaddress.ip_address(h)
        return ip.is_loopback
    except ValueError:
        return False


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    """
    HTTP redirect handler that enforces:
    - Same-origin redirection only (scheme, host, and port must match).
    - No cross-origin leaks of sensitive Authorization headers.
    - Rejection of downgrade from HTTPS to insecure HTTP.
    - Insecure HTTP redirects only permitted to validated loopback addresses.
    """
    def __init__(self, allow_http_loopback: bool = False):
        super().__init__()
        self.allow_http_loopback = allow_http_loopback

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        orig_parsed = urllib.parse.urlsplit(req.full_url)
        new_url_resolved = urllib.parse.urljoin(req.full_url, newurl)
        new_parsed = urllib.parse.urlsplit(new_url_resolved)

        if new_parsed.scheme not in ("https", "http"):
            raise urllib.error.HTTPError(
                new_url_resolved, code, f"Forbidden redirect scheme: {new_parsed.scheme}", headers, fp
            )

        if new_parsed.scheme == "http":
            if not (self.allow_http_loopback and is_loopback(new_parsed.hostname or "")):
                raise urllib.error.HTTPError(
                    new_url_resolved, code, "Forbidden redirect to insecure HTTP", headers, fp
                )

        orig_port = orig_parsed.port or (443 if orig_parsed.scheme == "https" else 80)
        new_port = new_parsed.port or (443 if new_parsed.scheme == "https" else 80)
        orig_host = (orig_parsed.hostname or "").lower()
        new_host = (new_parsed.hostname or "").lower()

        if (orig_parsed.scheme != new_parsed.scheme) or (orig_host != new_host) or (orig_port != new_port):
            raise urllib.error.HTTPError(
                new_url_resolved, code, "Cross-origin redirects are forbidden to prevent credential leakage", headers, fp
            )

        return super().redirect_request(req, fp, code, msg, headers, newurl)


def read_bounded(resp, max_bytes: int = MAX_RESPONSE_BYTES, chunk_size: int = 16384) -> bytes:
    """Reads response body with strict upper byte ceiling to prevent unbounded memory consumption."""
    content_length = resp.headers.get("Content-Length")
    if content_length and content_length.isdigit() and int(content_length) > max_bytes:
        raise ValueError(f"Response Content-Length {content_length} exceeds ceiling of {max_bytes} bytes")

    chunks = []
    total = 0
    while True:
        chunk = resp.read(chunk_size)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise ValueError(f"Response size exceeded ceiling of {max_bytes} bytes")
        chunks.append(chunk)
    return b"".join(chunks)


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
    """Fetches public holidays from Nager.Date API with local file caching and bounded response parsing."""
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
        opener = urllib.request.build_opener(SafeRedirectHandler(allow_http_loopback=False))
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "omarchy-calvomi/1.0",
                "Accept": "application/json",
            },
        )
        with opener.open(req, timeout=6) as resp:
            final_parsed = urllib.parse.urlsplit(resp.geturl())
            if final_parsed.scheme != "https":
                raise ValueError("Insecure redirect during holiday fetch")
            charset = resp.headers.get_content_charset() or "utf-8"
            raw_bytes = read_bounded(resp, max_bytes=MAX_RESPONSE_BYTES)
            raw = raw_bytes.decode(charset, errors="ignore")
            data = json.loads(raw) if raw.strip() else []
            if isinstance(data, list):
                sanitized_holidays = []
                for item in data[:200]:  # Cardinality cap: 200 holidays
                    if not isinstance(item, dict):
                        continue
                    dt = str(item.get("date", ""))[:10]
                    nm = sanitize_text(item.get("name") or "", 200)
                    loc = sanitize_text(item.get("localName") or "", 200)
                    if dt and nm:
                        sanitized_holidays.append({
                            "date": dt,
                            "name": nm,
                            "localName": loc,
                            "countryCode": country_code,
                        })
                write_atomic(cache_file, sanitized_holidays)
                return sanitized_holidays
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


def validate_url(url: str, has_credentials: bool = False) -> str:
    """
    Validates URL scheme and destination.
    Insecure HTTP is strictly rejected when credentials are present,
    unless targeting validated loopback addresses (127.0.0.1, ::1, localhost).
    """
    url = (url or "").strip()
    if not url:
        raise ValueError("URL cannot be empty")
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in ("https", "http"):
        raise ValueError(f"Invalid URL scheme: {parsed.scheme}. Must be https:// or http://")
    if not parsed.netloc or not parsed.hostname:
        raise ValueError("Invalid URL host")

    if parsed.scheme == "http" and has_credentials:
        if not is_loopback(parsed.hostname):
            raise ValueError(
                "Insecure HTTP scheme is not allowed with credentials unless using a loopback address (127.0.0.1, ::1, localhost)"
            )
    return url


def api_request(base_url, endpoint, api_key, method="GET", body=None, params=None, timeout=12):
    has_creds = bool(api_key)
    valid_base = validate_url(base_url, has_credentials=has_creds)
    url = urllib.parse.urljoin(valid_base.rstrip("/") + "/", endpoint.lstrip("/"))
    if params:
        url += "?" + urllib.parse.urlencode(params)

    headers = {
        "Accept": "application/json",
        "User-Agent": "omarchy-yuvomi-sync/2.0",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"

    base_parsed = urllib.parse.urlsplit(valid_base)
    allow_loopback = is_loopback(base_parsed.hostname or "")
    opener = urllib.request.build_opener(SafeRedirectHandler(allow_http_loopback=allow_loopback))

    req = urllib.request.Request(url, headers=headers, data=data, method=method)
    with opener.open(req, timeout=timeout) as resp:
        final_url = resp.geturl()
        final_parsed = urllib.parse.urlsplit(final_url)
        if final_parsed.scheme == "http" and has_creds and not is_loopback(final_parsed.hostname or ""):
            raise ValueError("Final URL resolved to insecure HTTP with credentials")

        charset = resp.headers.get_content_charset() or "utf-8"
        raw_bytes = read_bounded(resp, max_bytes=MAX_RESPONSE_BYTES)
        raw = raw_bytes.decode(charset, errors="ignore")
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
                raw_events = res.get("data") or res.get("events") or []
            elif isinstance(res, list):
                raw_events = res
            else:
                raw_events = []
            if isinstance(raw_events, list):
                events_data = [e for e in raw_events if isinstance(e, dict)][:1000]
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
        "events": normalized[:2000],
    }
    write_atomic(out_path, doc)
    print(f"Synced {min(len(normalized), 2000)} events (including {cc} holidays) to {out_path}")


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
