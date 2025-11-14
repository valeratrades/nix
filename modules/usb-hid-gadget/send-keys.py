#!/usr/bin/env python3
"""
USB HID Keyboard Gadget Helper Script

This script provides a simple interface to send keystrokes through
a USB HID keyboard gadget device (/dev/hidg0).

Usage:
    ./usb-hid-send-keys.py "Hello World"
    ./usb-hid-send-keys.py --file input.txt
    echo "test" | ./usb-hid-send-keys.py --stdin
"""

import argparse
import sys
import time
from pathlib import Path

# USB HID Keyboard keycodes (US layout)
KEYCODES = {
    # Letters
    'a': 0x04, 'b': 0x05, 'c': 0x06, 'd': 0x07, 'e': 0x08,
    'f': 0x09, 'g': 0x0a, 'h': 0x0b, 'i': 0x0c, 'j': 0x0d,
    'k': 0x0e, 'l': 0x0f, 'm': 0x10, 'n': 0x11, 'o': 0x12,
    'p': 0x13, 'q': 0x14, 'r': 0x15, 's': 0x16, 't': 0x17,
    'u': 0x18, 'v': 0x19, 'w': 0x1a, 'x': 0x1b, 'y': 0x1c,
    'z': 0x1d,

    # Numbers
    '1': 0x1e, '2': 0x1f, '3': 0x20, '4': 0x21, '5': 0x22,
    '6': 0x23, '7': 0x24, '8': 0x25, '9': 0x26, '0': 0x27,

    # Special characters (shifted numbers)
    '!': (0x02, 0x1e), '@': (0x02, 0x1f), '#': (0x02, 0x20),
    '$': (0x02, 0x21), '%': (0x02, 0x22), '^': (0x02, 0x23),
    '&': (0x02, 0x24), '*': (0x02, 0x25), '(': (0x02, 0x26),
    ')': (0x02, 0x27),

    # Punctuation
    ' ': 0x2c,      # Space
    '\n': 0x28,     # Enter
    '\t': 0x2b,     # Tab
    '-': 0x2d,      # Minus
    '=': 0x2e,      # Equal
    '[': 0x2f,      # Left bracket
    ']': 0x30,      # Right bracket
    '\\': 0x31,     # Backslash
    ';': 0x33,      # Semicolon
    "'": 0x34,      # Apostrophe
    '`': 0x35,      # Grave accent
    ',': 0x36,      # Comma
    '.': 0x37,      # Period
    '/': 0x38,      # Slash

    # Shifted punctuation
    '_': (0x02, 0x2d),  # Underscore (Shift + -)
    '+': (0x02, 0x2e),  # Plus (Shift + =)
    '{': (0x02, 0x2f),  # Left brace (Shift + [)
    '}': (0x02, 0x30),  # Right brace (Shift + ])
    '|': (0x02, 0x31),  # Pipe (Shift + \)
    ':': (0x02, 0x33),  # Colon (Shift + ;)
    '"': (0x02, 0x34),  # Double quote (Shift + ')
    '~': (0x02, 0x35),  # Tilde (Shift + `)
    '<': (0x02, 0x36),  # Less than (Shift + ,)
    '>': (0x02, 0x37),  # Greater than (Shift + .)
    '?': (0x02, 0x38),  # Question mark (Shift + /)

    # Special keys
    '\x1b': 0x29,   # Escape
    '\x08': 0x2a,   # Backspace
}

# Modifier keys
MOD_NONE = 0x00
MOD_LCTRL = 0x01
MOD_LSHIFT = 0x02
MOD_LALT = 0x04
MOD_LGUI = 0x08
MOD_RCTRL = 0x10
MOD_RSHIFT = 0x20
MOD_RALT = 0x40
MOD_RGUI = 0x80


class HIDKeyboard:
    """Interface to USB HID keyboard gadget"""

    def __init__(self, device_path: str = '/dev/hidg0', delay: float = 0.01):
        self.device_path = Path(device_path)
        self.delay = delay

        if not self.device_path.exists():
            raise FileNotFoundError(
                f"HID device not found: {device_path}\n"
                "Make sure USB HID gadget is configured and you have permissions."
            )

    def send_report(self, modifier: int, keycode: int):
        """Send a HID report (keystroke)"""
        report = bytes([modifier, 0x00, keycode, 0x00, 0x00, 0x00, 0x00, 0x00])
        with open(self.device_path, 'wb') as f:
            f.write(report)
        time.sleep(self.delay)

    def release_all(self):
        """Release all keys"""
        self.send_report(0x00, 0x00)

    def send_key(self, modifier: int, keycode: int):
        """Send a keystroke (press and release)"""
        self.send_report(modifier, keycode)
        self.release_all()

    def send_char(self, char: str):
        """Send a single character"""
        if char.isupper():
            # Uppercase letter: use shift
            keycode = KEYCODES.get(char.lower())
            if keycode:
                self.send_key(MOD_LSHIFT, keycode)
                return

        code = KEYCODES.get(char)
        if code is None:
            print(f"Warning: Unsupported character '{char}' (0x{ord(char):02x})", file=sys.stderr)
            return

        if isinstance(code, tuple):
            # Character requires modifier
            modifier, keycode = code
            self.send_key(modifier, keycode)
        else:
            # Simple character
            self.send_key(MOD_NONE, code)

    def send_string(self, text: str):
        """Send a string of text"""
        for char in text:
            self.send_char(char)


def main():
    parser = argparse.ArgumentParser(
        description='Send keystrokes via USB HID keyboard gadget',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  %(prog)s "Hello World"
  %(prog)s --file input.txt
  echo "test" | %(prog)s --stdin
  %(prog)s --delay 0.05 "Slower typing"
        '''
    )

    parser.add_argument('text', nargs='?', help='Text to type')
    parser.add_argument('-f', '--file', help='Read text from file')
    parser.add_argument('-s', '--stdin', action='store_true', help='Read text from stdin')
    parser.add_argument('-d', '--device', default='/dev/hidg0', help='HID device path (default: /dev/hidg0)')
    parser.add_argument('--delay', type=float, default=0.01, help='Delay between keystrokes in seconds (default: 0.01)')

    args = parser.parse_args()

    # Determine input source
    if args.file:
        with open(args.file, 'r') as f:
            text = f.read()
    elif args.stdin:
        text = sys.stdin.read()
    elif args.text:
        text = args.text
    else:
        parser.error("No input provided. Use positional argument, --file, or --stdin")

    # Send the text
    try:
        kbd = HIDKeyboard(device_path=args.device, delay=args.delay)
        kbd.send_string(text)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f"Error: Permission denied accessing {args.device}", file=sys.stderr)
        print("Make sure you're in the correct group or run with sudo", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
