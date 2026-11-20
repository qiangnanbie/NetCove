//
//  DesignTokens.swift
//  设计系统：对应原 App 的 RexDesign / RexDinoCore 模块（颜色、圆角、间距、字号）。
//  放在 Core：App 与 Script 调试面板都要用，避免模块间反向依赖。
//

import SwiftUI

enum DesignTokens {

    enum Accent {
        static let primary = Color(red: 0.34, green: 0.84, blue: 0.81)
        static let secondary = Color(red: 0.13, green: 0.52, blue: 0.63)
        static let warning = Color(red: 0.96, green: 0.62, blue: 0.27)
    }

    enum Surface {
        static let base = Color(red: 0.04, green: 0.07, blue: 0.14)
        static let raised = Color(red: 0.08, green: 0.12, blue: 0.20)
        static let overlay = Color.white.opacity(0.06)
    }

    enum Radius {
        static let card: CGFloat = 16
        static let pill: CGFloat = 22
        static let sheet: CGFloat = 28
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Typography {
        static let hero = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 15, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
    }

    /// 海报宽高比与原 App 一致：2:3 竖版 + 16:9 横版 hero。
    enum Aspect {
        static let poster: CGFloat = 2.0 / 3.0
        static let hero: CGFloat = 16.0 / 9.0
    }
}
