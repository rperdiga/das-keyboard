#!/usr/bin/env python3
"""
Keeps a Das Keyboard Q-series color applied: sets it now and again every time the keyboard reconnects.

The keyboard forgets its lighting whenever it loses USB power (reboot, replug, every KVM switch,
some sleep/wake cycles). This script stays running as a launchd agent, idle in a CFRunLoop, and
IOKit calls it back when a device with the Das Keyboard vendor ID arrives. It then re-runs
das_keyboard.py with the configured color or map. No polling.

install.sh --startup-color / --startup-map registers this as a LaunchAgent; you normally never run it by hand.
"""
import argparse
import ctypes
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SET_SCRIPT = os.path.join(HERE, 'das_keyboard.py')
LOG_DIR = os.path.expanduser('~/Library/Logs/das-keyboard')
LOG_FILE = os.path.join(LOG_DIR, 'watch.log')
VENDOR_ID = 0x24F0

cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
iokit = ctypes.CDLL('/System/Library/Frameworks/IOKit.framework/IOKit')
CFTypeRef = ctypes.c_void_p
CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, CFTypeRef)

cf.CFStringCreateWithCString.restype = CFTypeRef
cf.CFStringCreateWithCString.argtypes = [CFTypeRef, ctypes.c_char_p, ctypes.c_uint32]
cf.CFNumberCreate.restype = CFTypeRef
cf.CFNumberCreate.argtypes = [CFTypeRef, ctypes.c_int, ctypes.c_void_p]
cf.CFDictionaryCreateMutable.restype = CFTypeRef
cf.CFDictionaryCreateMutable.argtypes = [CFTypeRef, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]
cf.CFDictionarySetValue.argtypes = [CFTypeRef, CFTypeRef, CFTypeRef]
cf.CFRunLoopGetCurrent.restype = CFTypeRef
cf.CFRunLoopRun.restype = None
iokit.IOHIDManagerCreate.restype = CFTypeRef
iokit.IOHIDManagerCreate.argtypes = [CFTypeRef, ctypes.c_uint32]
iokit.IOHIDManagerSetDeviceMatching.argtypes = [CFTypeRef, CFTypeRef]
iokit.IOHIDManagerRegisterDeviceMatchingCallback.argtypes = [CFTypeRef, CALLBACK, ctypes.c_void_p]
iokit.IOHIDManagerScheduleWithRunLoop.argtypes = [CFTypeRef, CFTypeRef, CFTypeRef]
iokit.IOHIDManagerOpen.restype = ctypes.c_int
iokit.IOHIDManagerOpen.argtypes = [CFTypeRef, ctypes.c_uint32]


def log(msg):
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 200 * 1024:
            open(LOG_FILE, 'w').close()
        with open(LOG_FILE, 'a') as f:
            f.write('%s %s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), msg))
    except OSError:
        pass


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--color', help='color to apply (hex or name)')
    p.add_argument('--map', help='JSON layout file to apply')
    p.add_argument('--settle-seconds', type=float, default=3.0,
                   help='wait after an arrival event before talking to the keyboard (default 3)')
    a = p.parse_args()
    if a.map:
        set_args = ['--map', a.map]
    elif a.color:
        set_args = [a.color]
    else:
        p.error('specify --color or --map')

    state = {'last_apply': 0.0}

    def apply(reason):
        for attempt in range(1, 4):
            r = subprocess.run([sys.executable, '-I', SET_SCRIPT] + set_args, capture_output=True, text=True)
            out = (r.stdout + r.stderr).strip().replace('\n', ' | ')
            if r.returncode == 0:
                log('%s -> applied (attempt %d): %s' % (reason, attempt, out))
                state['last_apply'] = time.time()
                return
            log('%s -> attempt %d failed: %s' % (reason, attempt, out))
            time.sleep(3)

    def on_arrival(context, result, sender, device):
        # One physical plug produces several arrival events (one per HID collection); collapse them.
        if time.time() - state['last_apply'] < a.settle_seconds + 2:
            return
        time.sleep(a.settle_seconds)
        apply('device arrival')

    cb = CALLBACK(on_arrival)  # keep a reference so it is not garbage-collected
    mgr = iokit.IOHIDManagerCreate(None, 0)
    match = cf.CFDictionaryCreateMutable(None, 0, None, None)
    vid = ctypes.c_int32(VENDOR_ID)
    cf.CFDictionarySetValue(match, cf.CFStringCreateWithCString(None, b'VendorID', 0x08000100),
                            cf.CFNumberCreate(None, 3, ctypes.byref(vid)))
    iokit.IOHIDManagerSetDeviceMatching(mgr, match)
    iokit.IOHIDManagerRegisterDeviceMatchingCallback(mgr, cb, None)
    kCFRunLoopDefaultMode = cf.CFStringCreateWithCString(None, b'kCFRunLoopDefaultMode', 0x08000100)
    iokit.IOHIDManagerScheduleWithRunLoop(mgr, cf.CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)
    iokit.IOHIDManagerOpen(mgr, 0)

    log('watcher started (args: %s)' % ' '.join(set_args))
    # Devices already present fire the matching callback as soon as the run loop starts, which covers
    # the "apply at login" case. If the keyboard is absent we simply wait for it.
    state['last_apply'] = 0.0
    try:
        cf.CFRunLoopRun()
    finally:
        log('watcher stopped')


if __name__ == '__main__':
    main()
