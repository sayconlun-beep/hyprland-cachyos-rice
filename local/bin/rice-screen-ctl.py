#!/usr/bin/env python3
"""
Screen colour for the rice - the engine behind `rice-settings colour`.

Brightness, contrast and saturation are set on the PANEL over DDC/CI, the same
channel the monitor's own OSD buttons drive. That is deliberate: Hyprland's
sdrbrightness/sdrsaturation only do anything on an output that is in HDR mode,
and a gamma/shader trick would wash out the desktop, miss fullscreen games and
not survive a compositor restart. A DDC write lands in the monitor's own
memory, so it applies to everything on the wire and is still there after a
reboot - nothing here needs reapplying at login.

  rice-screen-ctl.py list                    JSON: every output, what it supports
  rice-screen-ctl.py show DP-1               JSON: that output's current values
  rice-screen-ctl.py set DP-1 --brightness 80 --contrast 55
  rice-screen-ctl.py reset DP-1              back to the values first seen here
  rice-screen-ctl.py detect                  re-probe buses and features

HDR lives next door in rice-monitor-ctl.py (`set DP-2 --hdr on`): it is a
Hyprland monitor rule, not a panel setting.

Talking to a monitor over i2c is slow - a probe of every feature costs a
second or two per panel, and `ddcutil detect` alone takes five. Buses and
feature support are therefore cached in ~/.cache/rice/screen-ddc.json, keyed
by the monitor's serial so re-plugging or swapping panels invalidates it.
Current VALUES are never cached: the OSD buttons can change them behind our
back, so `show` always reads them fresh.

Access needs no root and no group change: ddcutil's udev rule puts an ACL for
the seat user on /dev/i2c-*. If reads fail with a permission error, that rule
(or the i2c-dev module) is missing, not sudo.
"""

import argparse
import contextlib
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import time

HYPRCTL = os.environ.get("RICE_HYPRCTL", "hyprctl")
DDCUTIL = os.environ.get("RICE_DDCUTIL", "ddcutil")
CACHE_DIR = os.path.expanduser(os.environ.get("RICE_CACHE_DIR", "~/.cache/rice"))
CACHE = os.path.join(CACHE_DIR, "screen-ddc.json")

# VCP feature codes. 0x10 and 0x12 are near-universal; 0x8A is not - one panel
# here has it, the other answers "unsupported" - so the menu is built from what
# each panel actually answers, never from this list alone.
FEATURES = (
    ("brightness", "10", "Brightness"),
    ("contrast", "12", "Contrast"),
    ("saturation", "8A", "Colour saturation"),
)
BY_KEY = {key: (code, label) for key, code, label in FEATURES}

# ddcutil's own default sleep multiplier is fine for one panel here but not for
# the other, which needs longer gaps between i2c transactions or every other read
# comes back as a retry failure. Rather than slow every call down, a failed
# call is retried once at double the delay.
RETRY_SLEEP_MULTIPLIER = "2"

# How long to let a write settle before reading it back. A panel ACKs a setvcp
# it has no intention of keeping - a control greyed out inside a picture mode,
# or one a dynamic-contrast feature owns - and the revert takes a second or
# two, so a shorter wait would report a change that is not there. Neither
# panel here does it; the check is cheap and the alternative is lying.
SETTLE = 2.0

# A healthy DDC call answers in well under a second. One panel here wedges its
# i2c line every so often - one read during testing sat there for over a
# minute - so calls are cut short rather than hanging a menu on a panel that
# has stopped talking. The timeout is per attempt, and there are two.
TIMEOUT = 10


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def hyprctl_json(*args):
    if shutil.which(HYPRCTL) is None:
        die("hyprctl not found - is Hyprland running?", 3)
    try:
        out = subprocess.run([HYPRCTL, "-j", *args], capture_output=True,
                             text=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        die(f"hyprctl failed: {exc}", 3)
    if out.returncode != 0:
        die(f"hyprctl {' '.join(args)} failed: {out.stderr.strip()}", 3)
    try:
        return json.loads(out.stdout)
    except ValueError as exc:
        die(f"hyprctl returned unparseable JSON: {exc}", 3)


# ------------------------------------------------------------------ ddcutil --
def have_ddcutil():
    return shutil.which(DDCUTIL) is not None


@contextlib.contextmanager
def bus_lock(bus):
    """Serialise i2c traffic per bus across processes.

    DDC is a conversation, not a request: two ddcutil calls interleaved on one
    bus read each other's replies. Opening the menu twice should be harmless.
    """
    if bus is None:
        yield
        return
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, f"ddc-bus-{bus}.lock")
    with open(path, "w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX)
        except OSError:
            pass                                  # a lock we cannot take is not
        yield                                     # a reason to refuse the work


def ddc(args, bus=None, retry=True):
    """Run ddcutil, once more with longer i2c delays if it fails.

    Returns (ok, text). A monitor that is asleep or busy fails the first call
    and answers the second; a monitor that does not implement the feature
    fails both, fast enough that the retry costs little.
    """
    cmd = [DDCUTIL, "--brief"]
    if bus is not None:
        cmd += ["--bus", str(bus)]
    cmd += args
    try:
        with bus_lock(bus):
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return False, (f"no answer from the panel on i2c-{bus} within {TIMEOUT}s "
                       "- it may be asleep, or on another input")
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)
    text = (out.stdout or "").strip() or (out.stderr or "").strip()
    if out.returncode == 0 and "ERR" not in (out.stdout or ""):
        return True, text
    if retry:
        return ddc(args + ["--sleep-multiplier", RETRY_SLEEP_MULTIPLIER],
                   bus=bus, retry=False)
    return False, text


def detect_buses():
    """connector -> {bus, monitor} from `ddcutil detect`. Five seconds, so cached.

    Only outputs that answer DDC appear. The DRM connector line is what ties a
    bus to a Hyprland output name; the i2c bus numbers themselves are not
    stable across boots, and /sys/class/drm/*/ddc points at a DIFFERENT bus
    than the one ddcutil drives, so neither can be used as a shortcut.
    """
    ok, text = ddc(["detect"], retry=False)
    if not ok and "Display" not in text:
        return {}, text
    found, cur = {}, {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("Display "):
            cur = {}
        elif line.startswith("I2C bus:"):
            m = re.search(r"i2c-(\d+)", line)
            if m:
                cur["bus"] = int(m.group(1))
        elif line.startswith("DRM connector:"):
            # card1-DP-2 -> DP-2, the name Hyprland uses.
            cur["connector"] = re.sub(r"^card\d+-", "", line.split(":", 1)[1].strip())
        elif line.startswith("Monitor:"):
            cur["monitor"] = line.split(":", 1)[1].strip()
        if cur.get("bus") is not None and cur.get("connector") and cur.get("monitor"):
            found[cur["connector"]] = {"bus": cur["bus"], "monitor": cur["monitor"]}
            cur = {}
    return found, ""


def getvcp(bus, code):
    """(value, maximum) for one feature, or (None, None) if unsupported."""
    ok, text = ddc(["getvcp", code], bus=bus)
    if not ok:
        return None, None
    # "VCP 10 C 100 100" - code, type, current, max.
    m = re.match(r"^VCP\s+\S+\s+\S+\s+(\d+)\s+(\d+)", text)
    if not m:
        return None, None
    return int(m.group(1)), int(m.group(2))


def setvcp(bus, code, value):
    ok, text = ddc(["setvcp", code, str(value)], bus=bus)
    return ok, text


# -------------------------------------------------------------------- cache --
def load_cache():
    try:
        with open(CACHE) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_cache(data):
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp, CACHE)


def probe(connector, bus):
    """Which of FEATURES this panel answers. Costs one i2c read per feature."""
    supported = []
    for key, code, _label in FEATURES:
        value, _max = getvcp(bus, code)
        if value is not None:
            supported.append(key)
    return supported


def ddc_info(connectors, refresh=False):
    """connector -> {bus, monitor, supported}, probing only when the cache misses.

    The cached entry is trusted while the monitor string still matches what
    `detect` reports, so plugging a different panel into the same port
    re-probes instead of inheriting the old one's feature list.
    """
    cache = load_cache()
    entries = cache.get("outputs", {}) if not refresh else {}
    known = {c: e for c, e in entries.items()
             if isinstance(e, dict) and "bus" in e and "supported" in e}

    need = refresh or any(c not in known for c in connectors)
    detected, err = ({}, "")
    if need:
        detected, err = detect_buses()
        for conn, info in detected.items():
            old = known.get(conn)
            if old and old.get("monitor") == info["monitor"] and not refresh:
                continue
            known[conn] = {"bus": info["bus"], "monitor": info["monitor"],
                           "supported": probe(conn, info["bus"])}
        # An output that used to answer DDC but is gone from `detect` (turned
        # off, unplugged, switched to another input) keeps its entry: it will
        # be right again when the panel comes back, and dropping it would cost
        # another five-second detect.
        save_cache({"outputs": known})
    return known, err


# --------------------------------------------------------------- backlight --
def backlight_device():
    """An internal panel's backlight, for laptops - eDP has no DDC/CI.

    brightnessctl is already a rice dependency, so the laptop profile gets a
    working Brightness row instead of an empty menu. Contrast and saturation
    have no equivalent there and stay unsupported.
    """
    base = "/sys/class/backlight"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return None
    return names[0] if names else None


def backlight_value(device):
    try:
        with open(f"/sys/class/backlight/{device}/brightness") as fh:
            cur = int(fh.read().strip())
        with open(f"/sys/class/backlight/{device}/max_brightness") as fh:
            top = int(fh.read().strip())
    except (OSError, ValueError):
        return None, None
    if not top:
        return None, None
    return round(cur * 100 / top), 100


def backlight_set(device, percent):
    if shutil.which("brightnessctl") is None:
        return False, "brightnessctl not installed"
    try:
        out = subprocess.run(["brightnessctl", "-d", device, "set", f"{percent}%"],
                             capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)
    return out.returncode == 0, (out.stderr or out.stdout or "").strip()


# --------------------------------------------------------------- outputs --
def outputs(refresh=False):
    """Every enabled output, with the colour controls it actually has."""
    mons = [m for m in hyprctl_json("monitors", "all") if m.get("name")]
    names = [m["name"] for m in mons if not m.get("disabled")]
    info, err = ddc_info(names, refresh=refresh)

    internal = backlight_device()
    result = []
    for m in mons:
        name = m["name"]
        entry = info.get(name)
        item = {
            "connector": name,
            "model": m.get("model") or m.get("description") or "",
            "disabled": bool(m.get("disabled")),
            "bus": entry["bus"] if entry else None,
            "supported": list(entry["supported"]) if entry else [],
            "via": "ddc" if entry else None,
        }
        # eDP-1 on the laptop: no DDC bus, but a kernel backlight.
        if not entry and name.startswith("eDP") and internal:
            item.update(via="backlight", backlight=internal, supported=["brightness"])
        result.append(item)
    return result, err


def find_output(connector, refresh=False):
    outs, err = outputs(refresh=refresh)
    for o in outs:
        if o["connector"] == connector:
            return o, err
    die("unknown output %r - have: %s"
        % (connector, ", ".join(o["connector"] for o in outs) or "none"), 2)


def read_values(out):
    """Current value and range per supported control, read live from the panel."""
    values = {}
    for key in out["supported"]:
        code, label = BY_KEY[key]
        if out.get("via") == "backlight":
            value, top = backlight_value(out["backlight"])
        else:
            value, top = getvcp(out["bus"], code)
        values[key] = {"label": label, "value": value, "min": 0, "max": top or 100}
        if value is None:
            # Supported per the probe, but not answering now. Shown as unknown
            # so the menu still opens; setting it may well still work.
            values[key]["unreadable"] = True
    return values


# ------------------------------------------------------------- commands --
def cmd_list(args):
    outs, err = outputs(refresh=args.refresh)
    result = {"outputs": outs}
    if err:
        result["ddc_error"] = err
    if not have_ddcutil():
        result["ddc_error"] = "ddcutil not installed - pacman -S ddcutil"
    print(json.dumps(result, indent=2))
    return 0


def cmd_show(args):
    out, _err = find_output(args.connector, refresh=args.refresh)
    out["values"] = read_values(out)
    print(json.dumps(out, indent=2))
    return 0


def cmd_set(args):
    out, _err = find_output(args.connector)
    wanted = [(key, getattr(args, key)) for key, _c, _l in FEATURES
              if getattr(args, key) is not None]
    if not wanted:
        die("nothing to set - pass --brightness, --contrast or --saturation", 2)

    unsupported = [k for k, _v in wanted if k not in out["supported"]]
    if unsupported:
        die("%s does not support %s over DDC/CI%s"
            % (args.connector, ", ".join(unsupported),
               " (it answers: %s)" % ", ".join(out["supported"])
               if out["supported"] else " (it answers nothing - DDC/CI may be "
               "off in its OSD menu)"), 2)

    # The pre-change values are what `reset` puts back, and they are only
    # recorded ONCE per monitor: overwriting them on every set would make the
    # baseline drift into whatever was last applied.
    cache = load_cache()
    baselines = cache.setdefault("baseline", {})
    key_id = out.get("bus") if out.get("via") == "ddc" else out["connector"]
    mine = baselines.setdefault(str(key_id), {})
    before = read_values(out)
    changed = {}
    for key, value in wanted:
        limit = before.get(key, {}).get("max") or 100
        if not 0 <= value <= limit:
            die(f"{key} must be 0-{limit} on {args.connector}", 2)
        if key not in mine and before.get(key, {}).get("value") is not None:
            mine[key] = before[key]["value"]
        code, _label = BY_KEY[key]
        if out.get("via") == "backlight":
            ok, detail = backlight_set(out["backlight"], value)
        else:
            ok, detail = setvcp(out["bus"], code, value)
        changed[key] = {"value": value, "applied": ok}
        if not ok:
            changed[key]["detail"] = detail
    save_cache(cache)

    # Read the panel back. ddcutil reports what the MONITOR acknowledged, not
    # what it kept, so a control the panel locks (contrast inside a fixed
    # picture mode, brightness with a dynamic-contrast feature on) looks like a
    # success and silently does nothing.
    if any(c["applied"] for c in changed.values()):
        time.sleep(SETTLE)
        after = read_values(out)
        for key, info in changed.items():
            got = after.get(key, {}).get("value")
            if info["applied"] and got is not None and got != info["value"]:
                info["applied"] = False
                info["reverted_to"] = got
                info["detail"] = (
                    f"the panel took {info['value']} and went back to {got} - "
                    "something on the monitor owns this control (a picture "
                    "mode, or dynamic contrast), so it has to be changed in "
                    "the monitor's own OSD menu")

    ok = all(c["applied"] for c in changed.values())
    print(json.dumps({"connector": args.connector, "changed": changed,
                      "ok": ok}, indent=2))
    return 0 if ok else 1


def cmd_reset(args):
    out, _err = find_output(args.connector)
    cache = load_cache()
    key_id = out.get("bus") if out.get("via") == "ddc" else out["connector"]
    mine = (cache.get("baseline") or {}).get(str(key_id)) or {}
    if not mine:
        die(f"no saved baseline for {args.connector} - nothing has been changed "
            "here yet, so there is nothing to undo", 2)
    restored = {}
    for key, value in sorted(mine.items()):
        code, _label = BY_KEY[key]
        if out.get("via") == "backlight":
            ok, detail = backlight_set(out["backlight"], value)
        else:
            ok, detail = setvcp(out["bus"], code, value)
        restored[key] = {"value": value, "applied": ok}
        if not ok:
            restored[key]["detail"] = detail
    if all(c["applied"] for c in restored.values()):
        cache.get("baseline", {}).pop(str(key_id), None)
        save_cache(cache)
    print(json.dumps({"connector": args.connector, "restored": restored}, indent=2))
    return 0 if all(c["applied"] for c in restored.values()) else 1


def cmd_detect(_args):
    if not have_ddcutil():
        die("ddcutil not installed - pacman -S ddcutil", 3)
    outs, err = outputs(refresh=True)
    result = {"outputs": outs}
    if err:
        result["ddc_error"] = err
    print(json.dumps(result, indent=2))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    li = sub.add_parser("list", help="JSON dump of every output's colour controls")
    li.add_argument("--refresh", action="store_true", help="re-probe, ignore the cache")
    li.set_defaults(fn=cmd_list)

    sh = sub.add_parser("show", help="read one output's current values")
    sh.add_argument("connector")
    sh.add_argument("--refresh", action="store_true", help="re-probe, ignore the cache")
    sh.set_defaults(fn=cmd_show)

    s = sub.add_parser("set", help="change one output's colour")
    s.add_argument("connector")
    for key, _code, label in FEATURES:
        s.add_argument(f"--{key}", type=int, help=f"{label.lower()}, 0-100")
    s.set_defaults(fn=cmd_set)

    r = sub.add_parser("reset", help="restore the values this tool first saw")
    r.add_argument("connector")
    r.set_defaults(fn=cmd_reset)

    sub.add_parser("detect", help="re-probe buses and feature support") \
        .set_defaults(fn=cmd_detect)

    args = ap.parse_args(argv)
    if not have_ddcutil() and args.cmd in ("show", "set", "reset"):
        die("ddcutil not installed - pacman -S ddcutil", 3)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
