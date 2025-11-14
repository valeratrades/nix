# Example configuration for enabling USB HID Keyboard Gadget
#
# To use this module, add it to your NixOS configuration imports:
#
# imports = [
#   ./modules/usb-hid-gadget  # Imports default.nix from the directory
# ];
#
# Then enable and configure:

{ config, pkgs, ... }:

{
  # Import the module
  imports = [
    ./default.nix  # Or just reference the parent directory in your main config
  ];

  # Enable USB HID keyboard gadget
  hardware.usb-hid-gadget = {
    enable = true;

    # Optional: Customize the gadget
    gadgetName = "my_keyboard";
    manufacturer = "Your Name";
    product = "Virtual Keyboard";
    serialNumber = "12345678";

    # Allow users in 'wheel' group to write to /dev/hidg0
    hidDevicePermissions = "0660";
    hidDeviceGroup = "wheel";
  };

  # IMPORTANT: Add users who need to send keystrokes to the appropriate group
  users.users.youruser.extraGroups = [ "wheel" ];
}

# ============================================================================
# USAGE EXAMPLES
# ============================================================================
#
# After enabling this module and rebuilding your system, you can send
# keystrokes by writing 8-byte HID reports to /dev/hidg0
#
# HID Report Format (8 bytes):
# - Byte 0: Modifier keys bitmap
#   * 0x01 = Left Ctrl
#   * 0x02 = Left Shift
#   * 0x04 = Left Alt
#   * 0x08 = Left GUI (Super/Windows key)
#   * 0x10 = Right Ctrl
#   * 0x20 = Right Shift
#   * 0x40 = Right Alt
#   * 0x80 = Right GUI
# - Byte 1: Reserved (always 0x00)
# - Bytes 2-7: Up to 6 simultaneous key scan codes
#
# Common USB HID key codes:
# - 0x04 = 'a' / 'A'
# - 0x05 = 'b' / 'B'
# - 0x06 = 'c' / 'C'
# - 0x07 = 'd' / 'D'
# - 0x08 = 'e' / 'E'
# - 0x16 = 's' / 'S'
# - 0x1e = '1' / '!'
# - 0x28 = Enter
# - 0x2c = Space
# - 0x29 = Escape
# - See full list: https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf
#
# ============================================================================
# SHELL EXAMPLES
# ============================================================================
#
# 1. Type lowercase 'a':
#    echo -ne "\x00\x00\x04\x00\x00\x00\x00\x00" > /dev/hidg0  # Press 'a'
#    echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release all keys
#
# 2. Type uppercase 'A' (with shift):
#    echo -ne "\x02\x00\x04\x00\x00\x00\x00\x00" > /dev/hidg0  # Press Shift + 'a'
#    echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release all keys
#
# 3. Type Ctrl+C:
#    echo -ne "\x01\x00\x06\x00\x00\x00\x00\x00" > /dev/hidg0  # Press Ctrl + 'c'
#    echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release all keys
#
# 4. Type multiple keys simultaneously (e.g., 'abc'):
#    echo -ne "\x00\x00\x04\x05\x06\x00\x00\x00" > /dev/hidg0  # Press 'a', 'b', 'c'
#    echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release all keys
#
# ============================================================================
# PYTHON EXAMPLE
# ============================================================================
#
# import time
#
# # USB HID Keycodes
# KEY_A = 0x04
# KEY_ENTER = 0x28
# MOD_NONE = 0x00
# MOD_SHIFT = 0x02
#
# def send_key(dev, modifier, keycode):
#     """Send a single keystroke"""
#     # Press
#     report = bytes([modifier, 0x00, keycode, 0x00, 0x00, 0x00, 0x00, 0x00])
#     dev.write(report)
#     time.sleep(0.01)
#     # Release
#     report = bytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
#     dev.write(report)
#     time.sleep(0.01)
#
# def send_string(dev, text):
#     """Send a string of text"""
#     keymap = {
#         'a': (MOD_NONE, 0x04), 'A': (MOD_SHIFT, 0x04),
#         'b': (MOD_NONE, 0x05), 'B': (MOD_SHIFT, 0x05),
#         # Add more mappings as needed
#     }
#     for char in text:
#         if char in keymap:
#             mod, key = keymap[char]
#             send_key(dev, mod, key)
#
# # Usage
# with open('/dev/hidg0', 'wb') as hid:
#     send_string(hid, "Hello")
#     send_key(hid, MOD_NONE, KEY_ENTER)
#
# ============================================================================
# TROUBLESHOOTING
# ============================================================================
#
# 1. Check if UDC exists:
#    ls /sys/class/udc/
#
# 2. Check if gadget is configured:
#    ls /sys/kernel/config/usb_gadget/
#
# 3. Check service status:
#    systemctl status usb-hid-gadget
#
# 4. View service logs:
#    journalctl -u usb-hid-gadget -f
#
# 5. Manually test the setup:
#    sudo /nix/store/.../usb-hid-gadget-setup
#
# 6. Check permissions:
#    ls -la /dev/hidg0
#
# 7. If /dev/hidg0 doesn't exist, your hardware doesn't support gadget mode
#
