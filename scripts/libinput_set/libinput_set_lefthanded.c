#include <libinput.h>
#include <libudev.h>
#include <stdio.h>

int main() {
  struct libinput *li;
  struct libinput_device *device;
  struct udev *udev = udev_new();
  const char *device_path = "/dev/input/event7";

  if (!udev) {
    fprintf(stderr, "Failed to initialize udev\n");
    return -1;
  }

  // Create a libinput context
  li = libinput_path_create_context(NULL, NULL);
  if (!li) {
    fprintf(stderr, "Failed to initialize libinput context\n");
    udev_unref(udev);
    return -1;
  }

  // Add the device by its path
  device = libinput_path_add_device(li, device_path);
  if (!device) {
    fprintf(stderr, "Failed to find the device at %s\n", device_path);
    libinput_unref(li);
    udev_unref(udev);
    return -1;
  }

  // Set the device to left-handed mode
  enum libinput_config_status status =
      libinput_device_config_left_handed_set(device, 1);
  if (status == LIBINPUT_CONFIG_STATUS_SUCCESS) {
    printf("Left-handed mode enabled successfully.\n");
  } else {
    printf("Failed to enable left-handed mode.\n");
  }

  // Cleanup
  libinput_unref(li);
  udev_unref(udev);

  return 0;
}
