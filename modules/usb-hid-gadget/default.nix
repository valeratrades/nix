{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.usb-hid-gadget;

  # HID Report Descriptor for standard keyboard (boot protocol)
  # This descriptor defines a keyboard with 8 modifier keys and 6 regular key slots
  hidReportDescriptor = ''\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x03\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x03\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0'';

  setupScript = pkgs.writeShellScript "usb-hid-gadget-setup" ''
    set -euo pipefail

    # Ensure modules are loaded
    ${pkgs.kmod}/bin/modprobe libcomposite
    ${pkgs.kmod}/bin/modprobe usb_f_hid

    # Check if UDC exists
    if [ ! -d /sys/class/udc ]; then
      echo "ERROR: No USB Device Controller (UDC) found!"
      echo "This system does not support USB gadget mode."
      echo "USB gadget mode requires hardware with OTG or dual-role USB support."
      exit 1
    fi

    # Find the first available UDC
    UDC_NAME=$(ls /sys/class/udc | head -1)
    if [ -z "$UDC_NAME" ]; then
      echo "ERROR: No UDC devices available"
      exit 1
    fi

    GADGET_DIR="/sys/kernel/config/usb_gadget/${cfg.gadgetName}"

    # Clean up existing gadget if it exists
    if [ -d "$GADGET_DIR" ]; then
      echo "Cleaning up existing gadget configuration..."
      # Unbind from UDC if bound
      if [ -e "$GADGET_DIR/UDC" ]; then
        echo "" > "$GADGET_DIR/UDC" || true
      fi
      # Remove symlinks
      rm -f "$GADGET_DIR/configs/c.1/hid.usb0" || true
      # Remove directories
      rmdir "$GADGET_DIR/functions/hid.usb0" || true
      rmdir "$GADGET_DIR/strings/0x409" || true
      rmdir "$GADGET_DIR/configs/c.1/strings/0x409" || true
      rmdir "$GADGET_DIR/configs/c.1" || true
      rmdir "$GADGET_DIR" || true
    fi

    # Create gadget directory structure
    mkdir -p "$GADGET_DIR"
    cd "$GADGET_DIR"

    # Set USB device identifiers
    echo "${cfg.idVendor}" > idVendor
    echo "${cfg.idProduct}" > idProduct
    echo "0x0200" > bcdUSB       # USB 2.0
    echo "0x0100" > bcdDevice    # Device version 1.0

    # Device class (0x00 means each interface defines its own class)
    echo "0x00" > bDeviceClass
    echo "0x00" > bDeviceSubClass
    echo "0x00" > bDeviceProtocol

    # String descriptors
    mkdir -p strings/0x409
    echo "${cfg.serialNumber}" > strings/0x409/serialnumber
    echo "${cfg.manufacturer}" > strings/0x409/manufacturer
    echo "${cfg.product}" > strings/0x409/product

    # Create configuration
    mkdir -p configs/c.1
    mkdir -p configs/c.1/strings/0x409
    echo "Config 1: HID Keyboard" > configs/c.1/strings/0x409/configuration
    echo "${cfg.maxPower}" > configs/c.1/MaxPower

    # Create HID function
    mkdir -p functions/hid.usb0
    echo 1 > functions/hid.usb0/protocol     # 1 = Keyboard
    echo 1 > functions/hid.usb0/subclass     # 1 = Boot Interface Subclass
    echo 8 > functions/hid.usb0/report_length

    # Write HID report descriptor
    echo -ne "${hidReportDescriptor}" > functions/hid.usb0/report_desc

    # Link function to configuration
    ln -s functions/hid.usb0 configs/c.1/

    # Bind to UDC
    echo "Binding to UDC: $UDC_NAME"
    echo "$UDC_NAME" > UDC

    # Set permissions on the HID device
    sleep 1  # Give udev time to create the device
    if [ -e "/dev/hidg0" ]; then
      chmod ${cfg.hidDevicePermissions} /dev/hidg0
      ${optionalString (cfg.hidDeviceGroup != null) ''
        chgrp ${cfg.hidDeviceGroup} /dev/hidg0
      ''}
      echo "USB HID Keyboard gadget configured successfully!"
      echo "Write to /dev/hidg0 to send keystrokes"
    else
      echo "WARNING: /dev/hidg0 not found. The gadget may not be working."
      exit 1
    fi
  '';

  cleanupScript = pkgs.writeShellScript "usb-hid-gadget-cleanup" ''
    set -euo pipefail

    GADGET_DIR="/sys/kernel/config/usb_gadget/${cfg.gadgetName}"

    if [ -d "$GADGET_DIR" ]; then
      echo "Cleaning up USB HID gadget..."

      # Unbind from UDC
      if [ -e "$GADGET_DIR/UDC" ]; then
        echo "" > "$GADGET_DIR/UDC" || true
      fi

      # Remove symlinks
      rm -f "$GADGET_DIR/configs/c.1/hid.usb0" || true

      # Remove directories (in reverse order of creation)
      rmdir "$GADGET_DIR/configs/c.1/strings/0x409" || true
      rmdir "$GADGET_DIR/configs/c.1" || true
      rmdir "$GADGET_DIR/functions/hid.usb0" || true
      rmdir "$GADGET_DIR/strings/0x409" || true
      rmdir "$GADGET_DIR" || true

      echo "USB HID gadget cleaned up"
    fi
  '';

in {
  options.hardware.usb-hid-gadget = {
    enable = mkEnableOption "USB HID keyboard gadget mode";

    gadgetName = mkOption {
      type = types.str;
      default = "kbd_gadget";
      description = "Name for the USB gadget in configfs";
    };

    idVendor = mkOption {
      type = types.str;
      default = "0x1d6b";  # Linux Foundation
      description = "USB Vendor ID (hexadecimal)";
    };

    idProduct = mkOption {
      type = types.str;
      default = "0x0104";  # Multifunction Composite Gadget
      description = "USB Product ID (hexadecimal)";
    };

    manufacturer = mkOption {
      type = types.str;
      default = "NixOS";
      description = "Manufacturer string descriptor";
    };

    product = mkOption {
      type = types.str;
      default = "USB HID Keyboard";
      description = "Product string descriptor";
    };

    serialNumber = mkOption {
      type = types.str;
      default = "0123456789";
      description = "Serial number string descriptor";
    };

    maxPower = mkOption {
      type = types.int;
      default = 250;
      description = "Maximum power consumption in mA";
    };

    hidDevicePermissions = mkOption {
      type = types.str;
      default = "0660";
      description = "Permissions for /dev/hidg0 device";
    };

    hidDeviceGroup = mkOption {
      type = types.nullOr types.str;
      default = "wheel";
      description = "Group owner for /dev/hidg0 device (null for root)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure required kernel modules are available
    boot.kernelModules = [ "libcomposite" "usb_f_hid" ];

    # Mount configfs if not already mounted
    boot.kernelParams = [ "configfs.enable=1" ];

    # Ensure configfs is mounted
    systemd.tmpfiles.rules = [
      "d /sys/kernel/config 0755 root root - -"
    ];

    # Create systemd service to setup the USB gadget
    systemd.services.usb-hid-gadget = {
      description = "USB HID Keyboard Gadget";
      after = [ "sys-kernel-config.mount" "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${setupScript}";
        ExecStop = "${cleanupScript}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Add udev rule to set permissions on /dev/hidg0
    services.udev.extraRules = ''
      KERNEL=="hidg0", SUBSYSTEM=="hidg", MODE="${cfg.hidDevicePermissions}"${optionalString (cfg.hidDeviceGroup != null) '', GROUP="${cfg.hidDeviceGroup}"''}
    '';

    # Warn users if this is likely to fail
    warnings = mkIf cfg.enable [
      ''
        USB HID Gadget mode requires hardware with USB OTG or dual-role controller support.
        Most x86 laptops and desktops do NOT support this feature.
        If you see "No USB Device Controller (UDC) found" errors, your hardware does not support gadget mode.

        Supported hardware typically includes:
        - Raspberry Pi Zero/4
        - Embedded ARM boards (Odroid, BeagleBone, etc.)
        - Some tablets with USB-C OTG support

        To send keystrokes, write 8-byte HID reports to /dev/hidg0:
        - Byte 0: Modifier keys (bit flags: Ctrl, Shift, Alt, GUI)
        - Byte 1: Reserved (0x00)
        - Bytes 2-7: Up to 6 simultaneous key codes

        Example: echo -ne "\x00\x00\x04\x00\x00\x00\x00\x00" > /dev/hidg0  # Press 'a'
      ''
    ];
  };
}
