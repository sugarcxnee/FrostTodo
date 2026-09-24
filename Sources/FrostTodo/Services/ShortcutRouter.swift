import Foundation

/// 快捷键动作
public enum ShortcutAction: Equatable {
    /// 快速添加任务
    case quickAdd
    /// 开始或暂停计时
    case toggleTimer
    /// 完成当前任务
    case completeCurrent
}

/// 键位描述：字符 + 修饰键集合（command / shift / option / control）
public struct KeyboardShortcutDescriptor: Hashable, Codable {
    public var key: String
    public var modifiers: Set<String>

    public init(key: String, modifiers: Set<String>) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// 快捷键动作映射：键位到动作的纯逻辑路由，UI 层用菜单 keyboardShortcut 触发
public struct ShortcutRouter {
    public static let defaultMappings: [KeyboardShortcutDescriptor: ShortcutAction] = [
        KeyboardShortcutDescriptor(key: "n", modifiers: ["command"]): .quickAdd,
        KeyboardShortcutDescriptor(key: "t", modifiers: ["command", "shift"]): .toggleTimer,
        KeyboardShortcutDescriptor(key: "d", modifiers: ["command", "shift"]): .completeCurrent,
    ]

    private let mappings: [KeyboardShortcutDescriptor: ShortcutAction]

    public init(mappings: [KeyboardShortcutDescriptor: ShortcutAction] = ShortcutRouter.defaultMappings) {
        self.mappings = mappings
    }

    public func action(for key: String, modifiers: Set<String>) -> ShortcutAction? {
        mappings[KeyboardShortcutDescriptor(key: key.lowercased(), modifiers: modifiers)]
    }

    /// 执行计时相关动作（quickAdd 由视图层响应通知聚焦输入框）
    @MainActor
    public func perform(_ action: ShortcutAction, timer: TimerService) {
        switch action {
        case .toggleTimer:
            switch timer.phase {
            case .running:
                try? timer.pause()
            case .paused:
                try? timer.resume()
            case .idle:
                break
            }
        case .completeCurrent:
            _ = try? timer.completeActiveTask()
        case .quickAdd:
            break
        }
    }
}
