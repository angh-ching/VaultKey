import Foundation
import IOKit

/// Time since the last hardware input event. Used only for display; auto-lock
/// is driven by interaction with VaultKey so it cannot be stalled by a busy
/// virtual HID device.
public enum SystemIdle {
    public static func seconds() -> TimeInterval? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        return value.doubleValue / 1_000_000_000
    }
}
