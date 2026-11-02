import Carbon.HIToolbox
import DoyahCore

/// 全局快捷键的**真后端**（`FR-NTS-NOTE-CAPTURE-001` 判据①）：Carbon `RegisterEventHotKey`。
///
/// 为什么用 Carbon 而不是 `NSEvent.addGlobalMonitorForEvents`：后者要么需要「辅助功能」授权
/// （一开就弹系统授权框，而这条需求的口径是「一个动作」—— 先让人去系统设置里点授权就废了），
/// 要么只在应用处于前台时收得到键（那就不是全局）。`RegisterEventHotKey` 不需要授权、
/// 应用在后台也收得到，代价是这套 API 从 macOS 10 时代就没再变过 —— 但它还在。
public final class CarbonQuickCaptureHotKeyBackend: QuickCaptureHotKeyBackend {

    public init() {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    deinit { unregister() }

    @discardableResult
    public func register(_ shortcut: QuickCaptureShortcut, handler: @escaping () -> Void) -> Bool {
        unregister()
        callback = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let backend = Unmanaged<CarbonQuickCaptureHotKeyBackend>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                backend.callback?()
                return noErr
            },
            1,
            &eventType,
            context,
            &handlerRef
        )
        guard installStatus == noErr, let keyCode = Self.keyCode(for: shortcut.key) else {
            unregister()
            return false
        }

        // 签名固定成 'DYHQ'（Doyah Quick capture）：同一个应用里再有别的热键也不会撞 id。
        let hotKeyID = EventHotKeyID(signature: OSType(0x4459_4851), id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            Self.carbonModifiers(shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            unregister()
            return false
        }
        return true
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        callback = nil
    }

    /// 修饰键 → Carbon 掩码。Carbon 的 `cmdKey` / `optionKey` 等常量就是这套位。
    private static func carbonModifiers(_ modifiers: Set<QuickCaptureShortcut.Modifier>) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// 主键 → 虚拟键码。只收字母与数字（捕获键不会用功能键），认不出就报失败，
    /// 不猜 —— 猜错的结果是「热键注册成功但按了没反应」，比明确失败更难查。
    private static func keyCode(for key: String) -> UInt32? {
        switch key.lowercased() {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        default: return nil
        }
    }
}
