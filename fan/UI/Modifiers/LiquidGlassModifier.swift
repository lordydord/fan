//
//  LiquidGlassModifier.swift
//  ffan
//
//  Created by mohamad on 11/1/2026.
//

import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    var isInteractive = false
    var shadowOpacity: Double = 0.08
    
    func body(content: Content) -> some View {
        content
            .glassEffect(
                .clear
                    .tint(tint)
                    .interactive(false),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        isInteractive: Bool = false,
        shadowOpacity: Double = 0.08
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                isInteractive: isInteractive,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
