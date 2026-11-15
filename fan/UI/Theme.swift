//
//  Theme.swift
//  fan
//
//  Shared look, matching the Claude Usage menu-bar app: Liquid Glass cards, gradient
//  rings, small round glass buttons and a colourful but quiet palette.
//

import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Palette {
    static let cool = [Color(hex: 0x12C9A5), Color(hex: 0x22A6FF)]
    static let warm = [Color(hex: 0xFFB23F), Color(hex: 0xFF7A45)]
    static let hot = [Color(hex: 0xFF2D6F), Color(hex: 0xFF7A45)]
    static let fan = [Color(hex: 0x7B5CFF), Color(hex: 0x22A6FF)]
    static let boost = [Color(hex: 0x087A67), Color(hex: 0x0E8FA6)]
    static let accent = Color(hex: 0x6B4EF6)

    static func temperature(_ t: Double?) -> [Color] {
        guard let t else { return fan }
        if t >= 80 { return hot }
        if t >= 60 { return warm }
        return cool
    }

    static func sub(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xB9B8C6) : Color(hex: 0x55536A)
    }

    static func track(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color(hex: 0x1E1946, alpha: 0.10)
    }

    static func good(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x5EE3A1) : Color(hex: 0x157A45) }
    static func amber(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xFFC06B) : Color(hex: 0xB45309) }
    static func alert(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xFF7FA3) : Color(hex: 0xC8174D) }
}

// MARK: - Glass card

struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 18
    var edge: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .glassEffect(.regular, in: shape)
            .overlay(shape.strokeBorder(edge ?? (scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.7)),
                                        lineWidth: edge == nil ? 0.75 : 1.5))
    }
}

extension View {
    func card(radius: CGFloat = 18, edge: Color? = nil) -> some View {
        modifier(CardBackground(radius: radius, edge: edge))
    }
}

// MARK: - Pieces

struct Ring: View {
    var value: Double
    var colors: [Color]
    var lineWidth: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track(scheme), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(value, 1), 0.004))
                .stroke(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: String
    var spinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.rotate, options: .repeating, isActive: spinning)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(Palette.sub(scheme))
    }
}

/// A slim gradient bar, same proportions as the Claude Usage pace bars.
struct GradientBar: View {
    var value: Double
    var colors: [Color]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track(scheme))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * min(max(value, 0), 1), 6))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

/// Small temperature history line with a soft fill.
struct Sparkline: View {
    var values: [Double]
    var colors: [Color]

    var body: some View {
        GeometryReader { geo in
            let lo = (values.min() ?? 0) - 2, hi = (values.max() ?? 1) + 2
            let span = max(hi - lo, 1)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: values.count > 1 ? geo.size.width * CGFloat(i) / CGFloat(values.count - 1) : geo.size.width,
                        y: geo.size.height * (1 - CGFloat((v - lo) / span)))
            }
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [colors[0].opacity(0.28), colors[0].opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

/// Glass segmented control: the selected segment gets a tinted, interactive glass pill.
struct GlassSegmented<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var symbol: ((Value) -> String)? = nil
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let on = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    HStack(spacing: 4) {
                        if let symbol {
                            Image(systemName: symbol(option)).font(.system(size: 10, weight: .semibold))
                        }
                        Text(label(option)).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if on {
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.accent, Color(hex: 0x8A6CFF)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: Palette.accent.opacity(0.35), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
    }
}
