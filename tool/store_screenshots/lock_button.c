// Presses the Lock button of the iOS simulator it is spawned in:
//
//   xcrun simctl spawn <udid> lock_button
//
// Once locks the simulator and leaves the always-on display; once more
// wakes the Lock Screen. simctl has no command for it, and the Simulator
// app's own needs its window in front.
//
// The press is a HID event sent through IOKit's private event system
// client, which the simulator accepts from any process: consumer page
// 0x0C, usage 0x30 (Power).
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

typedef void *(*CreateClient)(CFAllocatorRef);
typedef void *(*CreateKeyboardEvent)(CFAllocatorRef, uint64_t, uint32_t,
                                     uint32_t, Boolean, uint32_t);
typedef void (*DispatchEvent)(void *, void *);

static void *iokit;

static void *symbol(const char *name) {
  void *found = dlsym(iokit, name);
  if (found == NULL) {
    fprintf(stderr, "lock_button: IOKit lacks %s\n", name);
    exit(1);
  }
  return found;
}

int main(void) {
  iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
  if (iokit == NULL) {
    fprintf(stderr, "lock_button: %s\n", dlerror());
    return 1;
  }
  CreateClient createClient = symbol("IOHIDEventSystemClientCreate");
  CreateKeyboardEvent createEvent = symbol("IOHIDEventCreateKeyboardEvent");
  DispatchEvent dispatch = symbol("IOHIDEventSystemClientDispatchEvent");
  void *client = createClient(kCFAllocatorDefault);
  for (int down = 1; down >= 0; down--) {
    void *event = createEvent(kCFAllocatorDefault, mach_absolute_time(), 0x0C,
                              0x30, down, 0);
    dispatch(client, event);
    CFRelease(event);
    usleep(120000);
  }
  return 0;
}
