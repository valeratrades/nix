# USB HID Keyboard Gadget for NixOS

This module enables your device to act as a USB HID keyboard when connected to another computer via USB, allowing you to programmatically send keystrokes.

## ⚠️ Hardware Requirements

**CRITICAL**: This feature requires specific hardware support that most laptops and desktops **DO NOT HAVE**.

### Required Hardware Features:

1. **USB OTG (On-The-Go) or Dual-Role Controller**: Your device must have a USB port that can operate in "device mode" or "peripheral mode", not just host mode.

2. **USB Device Controller (UDC)**: The system must expose a UDC via `/sys/class/udc/`

### Supported Hardware:

✅ **Typically Works:**
- Raspberry Pi Zero / Zero W / Zero 2 W
- Raspberry Pi 4 (via USB-C port)
- Raspberry Pi CM4 (via USB slave port)
- Embedded ARM boards (Odroid, BeagleBone, etc.)
- Some Android tablets with USB-C OTG
- Some specific laptops with USB-C OTG support (rare)

❌ **Typically Does NOT Work:**
- Most x86 laptops (including AMD Ryzen and Intel Core systems)
- Desktop computers
- Most standard laptops
- Devices with only USB-A or standard USB-C host ports

### Checking Hardware Support

Before enabling this module, verify your hardware supports gadget mode:

```bash
# Check if UDC exists (after loading modules)
sudo modprobe libcomposite
sudo modprobe usb_f_hid
ls /sys/class/udc/

# If the directory doesn't exist or is empty, your hardware doesn't support gadget mode
```

### Your Current System

Based on analysis of your system (AMD Ryzen 7 8840U with xHCI controllers), **your laptop likely DOES NOT support USB gadget mode**. The USB controllers detected are host-only controllers without dual-role capability.

## Installation

### 1. Add Module to Configuration

Add the module to your NixOS configuration:

```nix
# In your configuration.nix or flake imports
{
  imports = [
    ./modules/usb-hid-gadget  # Imports default.nix from the directory
  ];

  # Enable the gadget
  hardware.usb-hid-gadget = {
    enable = true;

    # Optional customization
    manufacturer = "Your Name";
    product = "Virtual Keyboard";
    serialNumber = "12345678";

    # Allow users in 'wheel' group to access /dev/hidg0
    hidDevicePermissions = "0660";
    hidDeviceGroup = "wheel";
  };

  # Make sure your user is in the appropriate group
  users.users.youruser.extraGroups = [ "wheel" ];
}
```

### 2. Rebuild System

```bash
sudo nixos-rebuild switch
```

### 3. Verify Setup

```bash
# Check if service started
systemctl status usb-hid-gadget

# Check if device exists
ls -la /dev/hidg0

# Check if gadget is configured
ls /sys/kernel/config/usb_gadget/
```

## Usage

### Method 1: Using the Python Helper Script

The easiest way to send keystrokes:

```bash
# Type a string
./modules/usb-hid-gadget/send-keys.py "Hello World"

# Type from a file
./modules/usb-hid-gadget/send-keys.py --file input.txt

# Type from stdin
echo "test message" | ./modules/usb-hid-gadget/send-keys.py --stdin

# Slower typing (adjust delay)
./modules/usb-hid-gadget/send-keys.py --delay 0.05 "Slower typing"
```

### Method 2: Direct Shell Commands

You can send raw HID reports directly to `/dev/hidg0`. Each report is 8 bytes:

**Format:**
- Byte 0: Modifier keys (Ctrl, Shift, Alt, GUI)
- Byte 1: Reserved (always 0x00)
- Bytes 2-7: Up to 6 simultaneous key codes

**Examples:**

```bash
# Type lowercase 'a'
echo -ne "\x00\x00\x04\x00\x00\x00\x00\x00" > /dev/hidg0  # Press
echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release

# Type uppercase 'A' (with Shift)
echo -ne "\x02\x00\x04\x00\x00\x00\x00\x00" > /dev/hidg0  # Shift + 'a'
echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release

# Type Ctrl+C
echo -ne "\x01\x00\x06\x00\x00\x00\x00\x00" > /dev/hidg0  # Ctrl + 'c'
echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0  # Release

# Press Enter
echo -ne "\x00\x00\x28\x00\x00\x00\x00\x00" > /dev/hidg0
echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0
```

### Method 3: Python Script

```python
#!/usr/bin/env python3
import time

def send_key(modifier, keycode):
    with open('/dev/hidg0', 'wb') as hid:
        # Press
        report = bytes([modifier, 0x00, keycode, 0x00, 0x00, 0x00, 0x00, 0x00])
        hid.write(report)
        time.sleep(0.01)
        # Release
        report = bytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        hid.write(report)
        time.sleep(0.01)

# Type 'a'
send_key(0x00, 0x04)

# Type 'A' (with shift)
send_key(0x02, 0x04)
```

## HID Key Codes Reference

### Modifier Keys (Byte 0)
- `0x01` - Left Ctrl
- `0x02` - Left Shift
- `0x04` - Left Alt
- `0x08` - Left GUI (Windows/Super key)
- `0x10` - Right Ctrl
- `0x20` - Right Shift
- `0x40` - Right Alt
- `0x80` - Right GUI

### Common Key Codes (Bytes 2-7)

**Letters:**
- `0x04-0x1d` - a-z

**Numbers:**
- `0x1e-0x27` - 1-9, 0

**Special Keys:**
- `0x28` - Enter
- `0x29` - Escape
- `0x2a` - Backspace
- `0x2b` - Tab
- `0x2c` - Space

**Function Keys:**
- `0x3a-0x45` - F1-F12

**Arrow Keys:**
- `0x4f` - Right Arrow
- `0x50` - Left Arrow
- `0x51` - Down Arrow
- `0x52` - Up Arrow

For complete reference, see: [USB HID Usage Tables](https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf)

## Configuration Options

```nix
hardware.usb-hid-gadget = {
  enable = true;

  # USB gadget name in configfs
  gadgetName = "kbd_gadget";

  # USB identifiers
  idVendor = "0x1d6b";   # Linux Foundation
  idProduct = "0x0104";   # Multifunction Composite Gadget

  # USB descriptors
  manufacturer = "NixOS";
  product = "USB HID Keyboard";
  serialNumber = "0123456789";

  # Power consumption in mA
  maxPower = 250;

  # /dev/hidg0 permissions
  hidDevicePermissions = "0660";
  hidDeviceGroup = "wheel";  # null for root only
};
```

## Troubleshooting

### Service won't start / "No UDC found" error

**Cause**: Your hardware doesn't support USB gadget mode.

**Solutions**:
1. Verify hardware support (see Hardware Requirements section)
2. If using a Raspberry Pi, make sure you're using the correct port:
   - Pi Zero: Micro USB port (not the power port)
   - Pi 4: USB-C port (may need `dtoverlay=dwc2` in `/boot/config.txt`)

### `/dev/hidg0` doesn't exist

**Cause**: Gadget didn't initialize properly.

**Check**:
```bash
# View service logs
journalctl -u usb-hid-gadget -f

# Check if modules loaded
lsmod | grep libcomposite

# Check configfs
ls /sys/kernel/config/usb_gadget/
```

### Permission denied when writing to `/dev/hidg0`

**Solutions**:
1. Check your user is in the correct group:
   ```bash
   groups  # Should include 'wheel' or configured group
   ```

2. Check device permissions:
   ```bash
   ls -la /dev/hidg0
   ```

3. Add user to group:
   ```bash
   sudo usermod -aG wheel yourusername
   # Then log out and back in
   ```

### Keystrokes not appearing on host

**Check**:
1. Correct USB cable (must support data, not just power)
2. USB port is in device/peripheral mode
3. Host computer recognizes the device:
   ```bash
   # On the host machine
   lsusb  # Should show "Linux Foundation" device
   ```

### Device shows as "Billboard device"

**Cause**: USB-C port negotiation failed or port doesn't support device mode.

**Try**:
- Different USB cable (must be USB-C to USB-C or USB-C to USB-A data cable)
- Different port on your device
- Check if your device has a specific USB "gadget" or "OTG" port

## Common Use Cases

### 1. KVM over IP Alternative

Control another computer's BIOS/firmware without a hardware KVM:

```bash
# Boot to BIOS (send F2 or DEL during boot)
echo -ne "\x00\x00\x3b\x00\x00\x00\x00\x00" > /dev/hidg0  # F2
echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00" > /dev/hidg0
```

### 2. Automated Typing

```bash
./modules/usb-hid-gadget/send-keys.py --file script.txt
```

### 3. Remote Control

Combine with SSH to remotely control a machine:

```bash
ssh yourdevice "./modules/usb-hid-gadget/send-keys.py 'password123' && sleep 1 && echo -ne '\x00\x00\x28\x00\x00\x00\x00\x00' > /dev/hidg0"
```

### 4. Security Testing (Authorized Only)

Bad USB / HID attack research in authorized penetration testing scenarios.

## Security Considerations

- **Physical access**: Once connected, this device has full keyboard access
- **Authorization**: Only use for authorized security testing
- **Malware risk**: Compromised device could inject keystrokes
- **Permissions**: Limit `/dev/hidg0` access to trusted users only

## Alternative Approaches

If your hardware doesn't support USB gadget mode:

1. **Hardware KVM**: Use a physical KVM switch or KVM over IP device
2. **USB Arduino/Teensy**: Use an Arduino/Teensy board as USB HID device
3. **Raspberry Pi Zero**: Dedicate a Pi Zero as a keyboard gadget
4. **Network-based tools**: Use tools like Synergy, Barrier, or SSH with X11 forwarding
5. **USB devices**: Use commercial USB HID injector devices

## References

- [Linux USB Gadget Documentation](https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html)
- [USB HID Usage Tables](https://www.usb.org/sites/default/files/documents/hut1_12v2.pdf)
- [Raspberry Pi OTG Mode](https://www.raspberrypi.org/documentation/hardware/computemodule/otg.md)

## Files in this Module

```
modules/usb-hid-gadget/
├── default.nix      - Main NixOS module
├── example.nix      - Example configuration with usage examples
├── send-keys.py     - Python helper script for easy keyboard input
└── README.md        - This documentation file
```

## License

These configuration files are provided as-is for educational and authorized use only.
