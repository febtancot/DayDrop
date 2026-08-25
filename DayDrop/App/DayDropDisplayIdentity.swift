import AppKit
import ColorSync

/// 与 ForNow 相同的 ColorSync 显示器身份规则。CGDirectDisplayID 可能在重连后变化，
/// URL 中只传稳定 UUID；少数虚拟显示器则在当前连接期间使用 runtime id。
enum DayDropDisplayIdentity {
    static func identifier(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else {
            return "runtime-\(number.uint32Value)"
        }
        let uuid = unmanagedUUID.takeRetainedValue()
        return (CFUUIDCreateString(nil, uuid) as String?)
            ?? "runtime-\(number.uint32Value)"
    }
}
