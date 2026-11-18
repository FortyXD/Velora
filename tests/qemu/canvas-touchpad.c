/* Two-finger input for the disposable QEMU guest. libinput recognizes this as a clickpad. */
#include <libevdev/libevdev-uinput.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static struct libevdev_uinput *device;
static void event(unsigned type, unsigned code, int value) { libevdev_uinput_write_event(device, type, code, value); }
static void axis(struct libevdev *dev, unsigned code, int max, int resolution) {
    struct input_absinfo info = {.minimum = 0, .maximum = max, .resolution = resolution};
    libevdev_enable_event_code(dev, EV_ABS, code, &info);
}
int main(int argc, char **argv) {
    if (access("/var/lib/velora-qemu-ready", F_OK) || argc != 2)
        return 2;
    int pinch = !strcmp(argv[1], "pinch");
    if (!pinch && strcmp(argv[1], "scroll"))
        return 2;
    struct libevdev *dev = libevdev_new();
    libevdev_set_name(dev, "Velora QEMU gesture fixture");
    libevdev_set_id_bustype(dev, BUS_USB);
    libevdev_set_id_vendor(dev, 0x1209);
    libevdev_set_id_product(dev, 0x570);
    libevdev_enable_property(dev, INPUT_PROP_POINTER);
    libevdev_enable_property(dev, INPUT_PROP_BUTTONPAD);
    const int keys[] = {BTN_LEFT, BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP, BTN_TOUCH};
    for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i)
        libevdev_enable_event_code(dev, EV_KEY, keys[i], NULL);
    axis(dev, ABS_X, 4000, 40);
    axis(dev, ABS_Y, 2400, 40);
    axis(dev, ABS_MT_POSITION_X, 4000, 40);
    axis(dev, ABS_MT_POSITION_Y, 2400, 40);
    axis(dev, ABS_MT_SLOT, 4, 0);
    axis(dev, ABS_MT_TRACKING_ID, 65535, 0);
    if (libevdev_uinput_create_from_device(dev, LIBEVDEV_UINPUT_OPEN_MANAGED, &device) < 0)
        return 1;
    usleep(750000);
    for (int i = 0; i < 26; ++i) {
        int dx = pinch ? i * 22 : 0, dy = pinch ? 0 : i * 22;
        event(EV_KEY, BTN_TOUCH, 1);
        event(EV_KEY, BTN_TOOL_DOUBLETAP, 1);
        for (int slot = 0; slot < 2; ++slot) {
            event(EV_ABS, ABS_MT_SLOT, slot);
            if (!i)
                event(EV_ABS, ABS_MT_TRACKING_ID, 40 + slot);
            event(EV_ABS, ABS_MT_POSITION_X, slot ? 2600 + dx : 1400 - dx);
            event(EV_ABS, ABS_MT_POSITION_Y, 850 + dy);
        }
        event(EV_ABS, ABS_X, 1400 - dx);
        event(EV_ABS, ABS_Y, 850 + dy);
        event(EV_SYN, SYN_REPORT, 0);
        usleep(12000);
    }
    for (int slot = 0; slot < 2; ++slot) {
        event(EV_ABS, ABS_MT_SLOT, slot);
        event(EV_ABS, ABS_MT_TRACKING_ID, -1);
    }
    event(EV_KEY, BTN_TOOL_DOUBLETAP, 0);
    event(EV_KEY, BTN_TOUCH, 0);
    event(EV_SYN, SYN_REPORT, 0);
    usleep(150000);
    libevdev_uinput_destroy(device);
    libevdev_free(dev);
    return 0;
}
