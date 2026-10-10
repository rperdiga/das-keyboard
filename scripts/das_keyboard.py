#!/usr/bin/env python3
"""
Control the RGB LEDs on a Das Keyboard 4Q / 5Q / 5QS directly over USB HID on macOS.
No Das Keyboard Q software, no Homebrew, no hidapi: only the system python3 and IOKit via ctypes.

Protocol from OpenRGB's DasKeyboardController (GPL-2.0-or-later); this is an independent
implementation. Colors are not saved to the keyboard's flash and revert when it loses USB power.

Usage:
  das_keyboard.py yellow                      whole keyboard
  das_keyboard.py FF0000 --keys wasd,arrows   only some keys
  das_keyboard.py cyan --mode Breathing       effect (Direct, Breathing, Flashing, SpectrumCycle)
  das_keyboard.py --map layout.json           several colors at once (applied top to bottom)
  das_keyboard.py --off                       lights off
  das_keyboard.py --info                      model, firmware, layout
  das_keyboard.py --list-keys                 all key, group and color names
"""
import argparse
import ctypes
import ctypes.util
import json
import re
import sys
import time

# ---------------------------------------------------------------------------
# Key table: LED id -> name (from OpenRGB's RGBController_DasKeyboard). Index = key id.
# ---------------------------------------------------------------------------
KEY_NAMES = [
    'LeftControl', 'LeftShift', 'CapsLock', 'Tab', 'Backtick', 'Escape', 'LeftWindows', 'Backslash',
    'A', 'Q', '1', None, 'LeftAlt', 'Z', 'S', 'W', '2', 'F1', None, 'X', 'D', 'E', '3', 'F2', None,
    'C', 'F', 'R', '4', 'F3', None, 'V', 'G', 'T', '5', 'F4', 'Space', 'B', 'H', 'Y', '6', 'F5', None,
    'N', 'J', 'U', '7', 'F6', None, 'M', 'K', 'I', '8', 'F7', None, 'Comma', 'L', 'O', '9', 'F8',
    'RightAlt', 'Period', 'Semicolon', 'P', '0', 'F9', 'RightWindows', 'Slash', 'Quote', 'LeftBracket',
    'Minus', 'F10', 'Menu', None, None, 'RightBracket', 'Equals', 'F11', 'RightControl', 'RightShift',
    'Enter', 'Pound', 'Backspace', 'F12', 'LeftArrow', None, None, 'Delete', 'Insert', 'PrintScreen',
    'DownArrow', 'UpArrow', None, 'End', 'Home', 'ScrollLock', 'RightArrow', None, None, 'PageDown',
    'PageUp', 'PauseBreak', 'Numpad0', 'Numpad1', 'Numpad4', 'Numpad7', 'NumLock', None, None,
    'Numpad2', 'Numpad5', 'Numpad8', 'NumpadDivide', None, 'NumpadPeriod', 'Numpad3', 'Numpad6',
    'Numpad9', 'NumpadTimes', None, None, None, 'NumpadEnter', 'NumpadPlus', 'NumpadMinus', None,
    'Sleep', 'Brightness', 'MediaPlayPause', 'MediaNext', 'QButton',
]
ALL_IDS = list(range(131))

ALIASES = {
    'esc': 'Escape', 'ctrl': 'LeftControl', 'lctrl': 'LeftControl', 'rctrl': 'RightControl',
    'control': 'LeftControl', 'shift': 'LeftShift', 'lshift': 'LeftShift', 'rshift': 'RightShift',
    'alt': 'LeftAlt', 'lalt': 'LeftAlt', 'ralt': 'RightAlt', 'option': 'LeftAlt', 'loption': 'LeftAlt',
    'roption': 'RightAlt', 'win': 'LeftWindows', 'lwin': 'LeftWindows', 'rwin': 'RightWindows',
    'windows': 'LeftWindows', 'super': 'LeftWindows', 'cmd': 'LeftWindows', 'command': 'LeftWindows',
    'lcmd': 'LeftWindows', 'rcmd': 'RightWindows', 'return': 'Enter', 'caps': 'CapsLock',
    'del': 'Delete', 'ins': 'Insert', 'prtsc': 'PrintScreen', 'printscreen': 'PrintScreen',
    'pgup': 'PageUp', 'pgdn': 'PageDown', 'pgdown': 'PageDown', 'pause': 'PauseBreak', 'break': 'PauseBreak',
    'up': 'UpArrow', 'down': 'DownArrow', 'left': 'LeftArrow', 'right': 'RightArrow',
    'grave': 'Backtick', 'tilde': 'Backtick', 'apostrophe': 'Quote', 'dash': 'Minus', 'hyphen': 'Minus',
    'dot': 'Period', 'bracketleft': 'LeftBracket', 'bracketright': 'RightBracket',
    'numpadmultiply': 'NumpadTimes', 'numpadstar': 'NumpadTimes', 'numpadsubtract': 'NumpadMinus',
    'numpadadd': 'NumpadPlus', 'numpaddot': 'NumpadPeriod', 'numpaddecimal': 'NumpadPeriod',
    'numpadslash': 'NumpadDivide', 'play': 'MediaPlayPause', 'playpause': 'MediaPlayPause',
    'next': 'MediaNext', 'qbutton': 'QButton', 'qkey': 'QButton', 'hash': 'Pound',
    'app': 'Menu', 'context': 'Menu',
}
for _n in range(10):
    ALIASES['num%d' % _n] = 'Numpad%d' % _n

GROUPS = {
    'letters': 'A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z',
    'numbers': '1,2,3,4,5,6,7,8,9,0',
    'fkeys': 'F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11,F12',
    'numpad': 'NumLock,NumpadDivide,NumpadTimes,NumpadMinus,NumpadPlus,NumpadEnter,NumpadPeriod,'
              'Numpad0,Numpad1,Numpad2,Numpad3,Numpad4,Numpad5,Numpad6,Numpad7,Numpad8,Numpad9',
    'arrows': 'UpArrow,DownArrow,LeftArrow,RightArrow',
    'nav': 'Insert,Delete,Home,End,PageUp,PageDown,PrintScreen,ScrollLock,PauseBreak',
    'modifiers': 'LeftControl,LeftShift,LeftAlt,LeftWindows,RightControl,RightShift,RightAlt,RightWindows,Menu',
    'wasd': 'W,A,S,D',
    'media': 'Sleep,Brightness,MediaPlayPause,MediaNext,QButton',
    'punctuation': 'Backtick,Minus,Equals,LeftBracket,RightBracket,Backslash,Semicolon,Quote,Comma,Period,Slash,Pound',
    'extras': 'Escape,Tab,CapsLock,Backspace,Enter,Space',
}

NAMED_COLORS = {
    'red': 'FF0000', 'green': '00FF00', 'blue': '0000FF', 'yellow': 'FFC800', 'lightyellow': 'FFFF80',
    'orange': 'FF5000', 'white': 'FFFFFF', 'cyan': '00FFFF', 'aqua': '00FFFF', 'magenta': 'FF00FF',
    'purple': '8000FF', 'violet': '8000FF', 'pink': 'FF2080', 'lime': '80FF00', 'teal': '008080',
    'gold': 'FFB000', 'amber': 'FFA000', 'warmwhite': 'FFD0A0', 'coolwhite': 'C0D8FF', 'gray': '404040',
    'grey': '404040', 'dim': '202020', 'off': '000000', 'black': '000000',
}

MODES = {'Direct': 0x01, 'Breathing': 0x08, 'SpectrumCycle': 0x14, 'Flashing': 0x1F}
KNOWN_PIDS = {0x2037: 'Das Keyboard 4Q', 0x2020: 'Das Keyboard 5Q', 0x209A: 'Das Keyboard 5QS'}
VENDOR_ID = 0x24F0

_LOWER_NAMES = {n.lower(): i for i, n in enumerate(KEY_NAMES) if n}


def _norm(tok):
    return tok.strip().lower().replace('_', '').replace('-', '').replace(' ', '')


def resolve_key_ids(spec):
    ids = []
    for raw in [t for t in spec.replace(';', ',').replace(' ', ',').split(',')]:
        if not raw:
            continue
        tok = _norm(raw)
        if tok in ('all', '*'):
            ids.extend(ALL_IDS)
            continue
        if tok in GROUPS:
            ids.extend(resolve_key_ids(GROUPS[tok]))
            continue
        if tok in ALIASES:
            tok = ALIASES[tok].lower()
        if tok not in _LOWER_NAMES:
            raise SystemExit("Unknown key or group '%s'. Run with --list-keys to see valid names." % raw)
        ids.append(_LOWER_NAMES[tok])
    seen, out = set(), []
    for i in ids:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out


def resolve_rgb(c):
    tok = _norm(str(c)).lstrip('#')
    tok = NAMED_COLORS.get(tok, tok).lower()
    if len(tok) != 6 or any(ch not in '0123456789abcdef' for ch in tok):
        raise SystemExit("Unknown color '%s'. Use 6 hex digits (FFC800) or a name like red, yellow, cyan, off." % c)
    return bytes.fromhex(tok)


def list_keys():
    print('Keys:')
    print(', '.join(n for n in KEY_NAMES if n))
    print('\nGroups:')
    for g in sorted(GROUPS):
        print('  %s = %s' % (g, GROUPS[g]))
    print('  all = every key')
    print('\nColors: hex (FFC800) or ' + ', '.join(sorted(NAMED_COLORS)))


# ---------------------------------------------------------------------------
# Low-level HID access through IOKit (ctypes, nothing to install)
# ---------------------------------------------------------------------------
cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
iokit = ctypes.CDLL('/System/Library/Frameworks/IOKit.framework/IOKit')

CFTypeRef = ctypes.c_void_p
kCFNumberSInt32Type = 3
kIOHIDReportTypeFeature = 2
kIOReturnSuccess = 0

cf.CFStringCreateWithCString.restype = CFTypeRef
cf.CFStringCreateWithCString.argtypes = [CFTypeRef, ctypes.c_char_p, ctypes.c_uint32]
cf.CFNumberGetValue.restype = ctypes.c_bool
cf.CFNumberGetValue.argtypes = [CFTypeRef, ctypes.c_int, ctypes.c_void_p]
cf.CFSetGetCount.restype = ctypes.c_long
cf.CFSetGetCount.argtypes = [CFTypeRef]
cf.CFSetGetValues.argtypes = [CFTypeRef, ctypes.POINTER(CFTypeRef)]
cf.CFRelease.argtypes = [CFTypeRef]
cf.CFGetTypeID.restype = ctypes.c_ulong
cf.CFGetTypeID.argtypes = [CFTypeRef]
cf.CFNumberGetTypeID.restype = ctypes.c_ulong

iokit.IOHIDManagerCreate.restype = CFTypeRef
iokit.IOHIDManagerCreate.argtypes = [CFTypeRef, ctypes.c_uint32]
iokit.IOHIDManagerSetDeviceMatching.argtypes = [CFTypeRef, CFTypeRef]
iokit.IOHIDManagerCopyDevices.restype = CFTypeRef
iokit.IOHIDManagerCopyDevices.argtypes = [CFTypeRef]
iokit.IOHIDDeviceGetProperty.restype = CFTypeRef
iokit.IOHIDDeviceGetProperty.argtypes = [CFTypeRef, CFTypeRef]
iokit.IOHIDDeviceOpen.restype = ctypes.c_int
iokit.IOHIDDeviceOpen.argtypes = [CFTypeRef, ctypes.c_uint32]
iokit.IOHIDDeviceClose.restype = ctypes.c_int
iokit.IOHIDDeviceClose.argtypes = [CFTypeRef, ctypes.c_uint32]
iokit.IOHIDDeviceSetReport.restype = ctypes.c_int
iokit.IOHIDDeviceSetReport.argtypes = [CFTypeRef, ctypes.c_int, ctypes.c_long, ctypes.c_char_p, ctypes.c_long]
iokit.IOHIDDeviceGetReport.restype = ctypes.c_int
iokit.IOHIDDeviceGetReport.argtypes = [CFTypeRef, ctypes.c_int, ctypes.c_long, ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]


def _cfstr(s):
    return cf.CFStringCreateWithCString(None, s.encode(), 0x08000100)


def _int_prop(dev, key):
    k = _cfstr(key)
    try:
        ref = iokit.IOHIDDeviceGetProperty(dev, k)
        if not ref or cf.CFGetTypeID(ref) != cf.CFNumberGetTypeID():
            return None
        v = ctypes.c_int32(0)
        return v.value if cf.CFNumberGetValue(ref, kCFNumberSInt32Type, ctypes.byref(v)) else None
    finally:
        cf.CFRelease(k)


class DasKeyboard:
    """Finds the Q-series 'system control' collection (usage page 1, usage 0x80) and talks to it."""

    def __init__(self):
        self.manager = iokit.IOHIDManagerCreate(None, 0)
        iokit.IOHIDManagerSetDeviceMatching(self.manager, None)
        devset = iokit.IOHIDManagerCopyDevices(self.manager)
        self.dev = None
        self.model = None
        if devset:
            n = cf.CFSetGetCount(devset)
            arr = (CFTypeRef * max(n, 1))()
            cf.CFSetGetValues(devset, arr)
            for i in range(n):
                d = arr[i]
                if _int_prop(d, 'VendorID') != VENDOR_ID:
                    continue
                pid = _int_prop(d, 'ProductID')
                if pid not in KNOWN_PIDS:
                    continue
                if _int_prop(d, 'PrimaryUsagePage') != 1 or _int_prop(d, 'PrimaryUsage') != 0x80:
                    continue
                size = _int_prop(d, 'MaxFeatureReportSize') or 0
                if size < 2:
                    continue
                if iokit.IOHIDDeviceOpen(d, 0) != kIOReturnSuccess:
                    continue
                self.dev = d
                self.model = KNOWN_PIDS[pid]
                self.report_len = 8  # report ID + 7 payload bytes (MaxFeatureReportSize reports 8)
                break
            cf.CFRelease(devset)
        if not self.dev:
            raise SystemExit('No Das Keyboard Q-series keyboard found (looked for USB VID 24F0 with PID 2037, 2020, or 209A). '
                             'Is it plugged in (directly or through the KVM) to this Mac?')

    def close(self):
        if self.dev:
            iokit.IOHIDDeviceClose(self.dev, 0)
            self.dev = None

    # Protocol (OpenRGB DasKeyboardController): report ID 1, payload + XOR checksum, chunked to the report size.
    def send(self, data):
        chk = 0
        for b in data:
            chk ^= b
        payload = bytes(data) + bytes([chk])
        chunk = self.report_len - 1
        for i in range(0, len(payload), chunk):
            buf = bytearray(self.report_len)
            buf[0] = 1
            part = payload[i:i + chunk]
            buf[1:1 + len(part)] = part
            ret = None
            for _ in range(4):
                ret = iokit.IOHIDDeviceSetReport(self.dev, kIOHIDReportTypeFeature, 1, bytes(buf), self.report_len)
                if ret == kIOReturnSuccess:
                    break
                time.sleep(0.005)
            if ret != kIOReturnSuccess:
                raise SystemExit('IOHIDDeviceSetReport failed (IOReturn 0x%x)' % (ret & 0xFFFFFFFF))
            time.sleep(0.001)

    def _get_chunk(self):
        buf = ctypes.create_string_buffer(self.report_len)
        buf[0] = b'\x01'
        n = ctypes.c_long(self.report_len)
        if iokit.IOHIDDeviceGetReport(self.dev, kIOHIDReportTypeFeature, 1, buf, ctypes.byref(n)) != kIOReturnSuccess:
            return None
        return bytes(buf.raw[:n.value])

    def receive(self):
        # Reads reply chunks until the keyboard returns an all-zero report. On macOS the returned
        # buffer holds the payload only (IOKit strips the report ID), 8 bytes per chunk.
        out = bytearray()
        for _ in range(32):
            b = self._get_chunk()
            if not b or not any(b):
                break
            out += b
        return bytes(out)

    def clear_stale(self):
        for _ in range(32):
            b = self._get_chunk()
            if not b or not any(b):
                break

    def send_key_color(self, key, mode_byte, rgb):
        if key < 130:
            self.send([0xEA, 0x08, 0x78, 0x08, key, mode_byte, rgb[0], rgb[1], rgb[2]])
        else:  # Q button: color only, no mode
            self.send([0xEA, 0x06, 0x78, 0x06, rgb[0], rgb[1], rgb[2]])

    def handshake(self):
        """Returns (firmware, layout) as strings; 'unknown' when the keyboard does not answer."""
        self.clear_stale()
        for attempt in range(5):
            self.send([0xEA, 0x02, 0xB0])
            time.sleep(0.01 + 0.02 * attempt)
            resp = self.receive()
            # Reply looks like: ED 14 B0 00 "S27116V24/S2749V31h". The two digits before the first
            # "V" are the layout code (16 or 63 = US), the digits after each "V" are the firmware.
            m = re.search(rb'(\d\d)V(\d+)/S\d*V(\d+)', resp)
            if m:
                layout = 'US' if m.group(1) in (b'16', b'63') else 'EU'
                return 'V%s.%s.0' % (m.group(2).decode(), m.group(3).decode()), layout
        return 'unknown', 'unknown'


def main(argv=None):
    p = argparse.ArgumentParser(description='Set Das Keyboard 4Q/5Q/5QS backlight colors on macOS.')
    p.add_argument('color', nargs='?', help='hex (FFC800, #ff0000) or a name (red, yellow, cyan, off, ...)')
    p.add_argument('--keys', '-k', help='comma-separated key names and/or groups; default: every key')
    p.add_argument('--mode', '-m', default='Direct', choices=sorted(MODES), type=lambda s: {k.lower(): k for k in MODES}.get(s.lower(), s))
    p.add_argument('--map', help='JSON file mapping key/group names to colors, applied in file order')
    p.add_argument('--off', action='store_true', help='turn every LED off')
    p.add_argument('--info', action='store_true', help='print model, firmware and layout, then exit')
    p.add_argument('--list-keys', action='store_true', help='print every key, group and color name, then exit')
    a = p.parse_args(argv)

    if a.list_keys:
        list_keys()
        return 0
    if sum(bool(x) for x in (a.map, a.off, a.info)) > 1:
        p.error('use only one of --map, --off, --info')

    # Validate inputs before touching the keyboard.
    changes = []  # (ids, rgb, label)
    if a.off:
        changes.append((ALL_IDS, b'\0\0\0', 'all keys off'))
    elif a.map:
        with open(a.map) as f:
            layout = json.load(f)
        if not isinstance(layout, dict):
            raise SystemExit('--map file must be a JSON object like {"all": "dim", "wasd": "red"}')
        for name, val in layout.items():
            changes.append((resolve_key_ids(name), resolve_rgb(val), '%s -> %s' % (name, val)))
    elif not a.info:
        if not a.color:
            p.error('specify a color (e.g. yellow), or use --off, --map, --info, or --list-keys')
        ids = resolve_key_ids(a.keys) if a.keys else ALL_IDS
        changes.append((ids, resolve_rgb(a.color), '%s -> %s' % (a.keys or 'all keys', a.color)))

    kb = DasKeyboard()
    try:
        fw, layout = kb.handshake()
        print('Found %s, firmware %s, %s layout' % (kb.model, fw, layout))
        if a.info:
            return 0
        if fw == 'unknown':
            print('Warning: keyboard did not answer the handshake; sending colors anyway.', file=sys.stderr)
        mode_byte = MODES[a.mode]
        for ids, rgb, _ in changes:
            for key in ids:
                kb.send_key_color(key, mode_byte, rgb)
        kb.send([0xEA, 0x03, 0x78, 0x0A])  # apply
        kb.receive()
        for _, _, label in changes:
            print('Set %s (%s)' % (label, a.mode))
        return 0
    finally:
        kb.close()


if __name__ == '__main__':
    sys.exit(main())
