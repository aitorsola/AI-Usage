//
//  iOSSupport.swift
//  AI Usage (iOS)
//
//  Copyright © 2026 Aitor Sola. All rights reserved.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

extension ProviderKind {
    // The provider's brand color, derived from the shared hex so the iOS UI
    // matches the macOS app and the widget without pulling in AppKit views.
    var brand: Color { Color(hex: colorHex) }
}
