import SwiftUI
import AppKit

// MARK: - 十六进制颜色

extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension Color {
    /// 深浅色自适应颜色
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        let nsColor = NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua
            return match == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
        return Color(nsColor: nsColor)
    }
}

// MARK: - 冷色主题

/// Frost 冷色调：低饱和、克制，支持深色模式
public enum FrostTheme {
    /// 背景：浅 #F4F8FC / 深 #16202B
    public static let background = Color.dynamic(light: 0xF4F8FC, dark: 0x16202B)
    /// 卡片背景：浅 #FFFFFF / 深 #1D2A38
    public static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x1D2A38)
    /// 主色 #4A90E2
    public static let primary = Color(hex: 0x4A90E2)
    /// 辅助色 #7FB3D5
    public static let secondary = Color.dynamic(light: 0x7FB3D5, dark: 0x6E9FC0)
    /// 浅强调：浅 #A8C7E6 / 深 #33506E
    public static let accent = Color.dynamic(light: 0xA8C7E6, dark: 0x33506E)
    /// 主文本：浅 #1F2A37 / 深 #D6E4F0
    public static let text = Color.dynamic(light: 0x1F2A37, dark: 0xD6E4F0)
    /// 次级文本
    public static let secondaryText = Color.dynamic(light: 0x5B7186, dark: 0x8FA6BC)
    /// 成功 #4CAF93
    public static let success = Color(hex: 0x4CAF93)
    /// 警告 #E6A23C
    public static let warning = Color(hex: 0xE6A23C)
    /// 分隔线
    public static let separator = Color.dynamic(light: 0xDCE7F2, dark: 0x2A3A4D)
}

extension Color {
    init(hex: UInt32) {
        self.init(NSColor(hex: hex))
    }
}

// MARK: - 常用格式化

@MainActor
enum Formatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func duration(_ seconds: Int) -> String {
        TimerViewModel.format(seconds: seconds)
    }
}
