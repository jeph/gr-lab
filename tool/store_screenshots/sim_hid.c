// Presses the Lock button of the iOS simulator it is spawned in, or taps
// its screen:
//
//   xcrun simctl spawn <udid> sim_hid lock
//   xcrun simctl spawn <udid> sim_hid tap <x> <y>
//
// `lock` locks the simulator and leaves the always-on display; once more
// wakes the Lock Screen. `tap` takes a point as fractions of the screen's
// width and height. simctl has no command for either, and the Simulator
// app's own need its window in front.
//
// Both are HID events sent through IOKit's private event system client,
// which the simulator accepts from any process: the button as consumer
// page 0x0C, usage 0x30 (Power), the tap as a finger on a digitizer that
// is the display.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef void *(*CreateClient)(CFAllocatorRef);
typedef void *(*CreateKeyboardEvent)(CFAllocatorRef, uint64_t, uint32_t,
                                     uint32_t, Boolean, uint32_t);
typedef void *(*CreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t,
                                      uint32_t, uint32_t, uint32_t, uint32_t,
                                      double, double, double, double, double,
                                      Boolean, Boolean, uint32_t);
typedef void *(*CreateFingerEvent)(CFAllocatorRef, uint64_t, uint32_t,
                                   uint32_t, uint32_t, double, double, double,
                                   double, double, Boolean, Boolean, uint32_t);
typedef void (*AppendEvent)(void *, void *, uint32_t);
typedef void (*SetIntegerValue)(void *, uint32_t, long);
typedef void (*SetSenderID)(void *, uint64_t);
typedef void (*DispatchEvent)(void *, void *);

// kIOHIDDigitizerTransducerTypeHand.
static const uint32_t hand = 3;
// kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch.
static const uint32_t rangeAndTouch = 0x3;
// kIOHIDEventFieldDigitizerIsDisplayIntegrated.
static const uint32_t isDisplayIntegrated = 0xB0019;
// The sender the system takes for its own touch screen.
static const uint64_t touchScreen = 0x8000000817319372ULL;

static void *iokit;

static void *symbol(const char *name) {
  void *found = dlsym(iokit, name);
  if (found == NULL) {
    fprintf(stderr, "sim_hid: IOKit lacks %s\n", name);
    exit(1);
  }
  return found;
}

static void lock(void *client, DispatchEvent dispatch) {
  CreateKeyboardEvent create = symbol("IOHIDEventCreateKeyboardEvent");
  for (int down = 1; down >= 0; down--) {
    void *event =
        create(kCFAllocatorDefault, mach_absolute_time(), 0x0C, 0x30, down, 0);
    dispatch(client, event);
    CFRelease(event);
    usleep(120000);
  }
}

static void tap(void *client, DispatchEvent dispatch, double x, double y) {
  CreateDigitizerEvent createHand = symbol("IOHIDEventCreateDigitizerEvent");
  CreateFingerEvent createFinger =
      symbol("IOHIDEventCreateDigitizerFingerEvent");
  AppendEvent append = symbol("IOHIDEventAppendEvent");
  SetIntegerValue setInteger = symbol("IOHIDEventSetIntegerValue");
  SetSenderID setSender = symbol("IOHIDEventSetSenderID");
  for (int down = 1; down >= 0; down--) {
    uint64_t now = mach_absolute_time();
    void *event = createHand(kCFAllocatorDefault, now, hand, 0, 0,
                             rangeAndTouch, 0, x, y, 0, 0, 0, down, down, 0);
    setInteger(event, isDisplayIntegrated, 1);
    void *finger = createFinger(kCFAllocatorDefault, now, 1, 2, rangeAndTouch,
                                x, y, 0, down, 0, down, down, 0);
    append(event, finger, 0);
    setSender(event, touchScreen);
    dispatch(client, event);
    CFRelease(finger);
    CFRelease(event);
    usleep(90000);
  }
}

int main(int argc, char **argv) {
  int locks = argc == 2 && strcmp(argv[1], "lock") == 0;
  int taps = argc == 4 && strcmp(argv[1], "tap") == 0;
  if (!locks && !taps) {
    fprintf(stderr, "usage: sim_hid lock | sim_hid tap <x> <y>\n");
    return 64;
  }
  iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
  if (iokit == NULL) {
    fprintf(stderr, "sim_hid: %s\n", dlerror());
    return 1;
  }
  CreateClient createClient = symbol("IOHIDEventSystemClientCreate");
  DispatchEvent dispatch = symbol("IOHIDEventSystemClientDispatchEvent");
  void *client = createClient(kCFAllocatorDefault);
  if (locks) {
    lock(client, dispatch);
  } else {
    tap(client, dispatch, atof(argv[2]), atof(argv[3]));
  }
  return 0;
}
