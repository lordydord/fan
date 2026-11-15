//
//  PopoverView.swift
//  fan
//
//  The menu-bar popover. Same structure and look as Claude Usage: a compact header,
//  twin gauge cards, glass cards for the controls and a teal action card.
//

import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var settings: FanSettings
    @ObservedObject var controller: FanController
    @ObservedObject private var permissions = PermissionsManager.shared
    @ObservedObject private var battery = BatteryMonitor.shared

    @State private var showingSettings = false

    var body: some View {
        ZStack {
            if showingSettings {
                SettingsView(viewModel: viewModel, settings: settings,
                             back: { withAnimation(.snappy) { showingSettings = false } })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                DashboardView(viewModel: viewModel, settings: settings, controller: controller,
                              permissions: permissions, battery: battery,
                              openSettings: { withAnimation(.snappy) { showingSettings = true } })
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 12))
        .monospacedDigit()
        .onAppear {
            if !viewModel.isMonitoring { viewModel.startMonitoring() }
            battery.startMonitoring()
        }
        .onDisappear {
            if settings.menuBarDisplay != .power { battery.stopMonitoring() }
        }
    }
}

// MARK: - Dashboard

private struct DashboardView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var settings: FanSettings
    @ObservedObject var controller: FanController
    @ObservedObject var permissions: PermissionsManager
    @ObservedObject var battery: BatteryMonitor
    let openSettings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovered: String?
    @State private var installError: String?

    private var sub: Color { Palette.sub(scheme) }
    private var hottest: Double? { viewModel.getMaxTemperature() > 0 ? viewModel.getMaxTemperature() : nil }
    private var tempColors: [Color] { Palette.temperature(hottest) }
    private var tempFraction: Double { hottest.map { max(0.04, min(1, ($0 - 30) / 70)) } ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            header
            if !permissions.isHelperInstalled {
                setupCard
            } else if !viewModel.hasAccess {
                stateCard(symbol: "lock.trianglebadge.exclamationmark.fill", colors: Palette.warm,
                          title: "System access needed",
                          message: viewModel.lastError ?? "Fan App can’t read the thermal sensors yet.")
            } else if viewModel.cpuTemperature == nil {
                stateCard(symbol: "waveform.path.ecg", colors: Palette.fan,
                          title: "Reading your Mac", message: "The first reading can take a moment.")
            } else {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            temperatureGauge
                            fanGauge
                        }
                        if viewModel.thermalHistory.count >= 3 { trendCard }
                        coolingCard
                        if settings.mode != .maximum { boostCard }
                    }
                }
            }
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Ring(value: tempFraction, colors: tempColors, lineWidth: 2.6)
                .frame(width: 15, height: 15)
            Text("Fan App").font(.system(size: 13, weight: .semibold))
            Spacer()
            RoundIconButton(symbol: "gearshape", label: "Settings", action: openSettings)
        }
        .frame(height: 28)
        .padding(.horizontal, 2)
    }

    // MARK: Gauges

    private var temperatureGauge: some View {
        let cpu = viewModel.cpuTemperature, gpu = viewModel.gpuTemperature
        let source = (gpu ?? 0) > (cpu ?? 0) ? "GPU" : "CPU"
        let detail: String = {
            if hovered == "temp" {
                return [cpu.map { "CPU \(Int($0.rounded()))°" }, gpu.map { "GPU \(Int($0.rounded()))°" }]
                    .compactMap { $0 }.joined(separator: " · ")
            }
            return temperatureStatus
        }()
        return gauge(id: "temp", value: tempFraction, colors: tempColors,
                     big: hottest.map { "\(Int($0.rounded()))" } ?? "–", unit: "°", small: source,
                     title: "Temperature", detail: detail)
    }

    private var fanGauge: some View {
        let rpm = viewModel.currentFanSpeed
        let detail: String = {
            if hovered == "fan", controller.targetSpeed > 0 { return "Target \(controller.targetSpeed.formatted()) RPM" }
            return rpm > 0 ? "\(rpm.formatted()) RPM" : "Fans resting"
        }()
        return gauge(id: "fan", value: viewModel.fanFraction, colors: Palette.fan,
                     big: "\(viewModel.fanPercent)", unit: "%", small: "speed",
                     title: viewModel.numberOfFans == 1 ? "Fan" : "Fans", detail: detail)
    }

    private func gauge(id: String, value: Double, colors: [Color], big: String, unit: String,
                       small: String, title: String, detail: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Ring(value: value, colors: colors, lineWidth: 9)
                VStack(spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(big).font(.system(size: 23, weight: .bold, design: .rounded))
                        Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(sub)
                    }
                    Text(small).font(.system(size: 10)).foregroundStyle(sub)
                }
            }
            .frame(width: 88, height: 88)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 11)).foregroundStyle(sub)
                .lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12).padding(.bottom, 10).padding(.horizontal, 6)
        .card(radius: 20)
        .onHover { inside in
            if inside { hovered = id } else if hovered == id { hovered = nil }
        }
    }

    private var temperatureStatus: String {
        guard let t = hottest else { return "Reading" }
        if t < 55 { return "Cool" }
        if t < 70 { return "Comfortable" }
        if t < 85 { return "Running warm" }
        return "Running hot"
    }

    // MARK: Trend

    private var trendCard: some View {
        let temps = viewModel.thermalHistory.map(\.temperature)
        let lo = Int((temps.min() ?? 0).rounded()), hi = Int((temps.max() ?? 0).rounded())
        let minutes = max(1, Int((viewModel.thermalHistory.last?.date.timeIntervalSince(viewModel.thermalHistory.first?.date ?? .now) ?? 60) / 60))
        return VStack(spacing: 8) {
            HStack {
                SectionLabel("Last \(minutes) min")
                Spacer()
                Text(lo == hi ? "\(lo)°" : "\(lo)–\(hi)°").font(.system(size: 10, weight: .semibold)).foregroundStyle(sub)
            }
            Sparkline(values: temps, colors: tempColors)
                .frame(height: 30)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .card()
    }

    // MARK: Cooling

    private var modeBinding: Binding<ControlMode> {
        Binding(get: { settings.mode }, set: { controller.setMode($0) })
    }

    private var coolingCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SectionLabel("Cooling")
                Spacer()
                status
            }
            GlassSegmented(options: ControlMode.allCases, selection: modeBinding,
                           label: { $0.label }, symbol: { $0.symbol })

            Group {
                switch settings.mode {
                case .system:
                    note(settings.autoSwitchWhenHot
                         ? "macOS manages the fans. Fan App steps in with Smart above \(Int(settings.highTempAlert))°."
                         : "macOS manages the fans. Fan App just watches the sensors.")
                case .automatic:
                    smartControls
                case .manual:
                    sliderRow("Speed", value: "\(settings.manualSpeed.formatted()) RPM",
                              binding: Binding(get: { Double(settings.manualSpeed) },
                                               set: { settings.setManualSpeed(Int($0)) }),
                              range: 1000...6500, step: 100)
                case .maximum:
                    note("Every fan at full speed, \(FanSettings.maxRPM.formatted()) RPM.")
                }
            }
            .transition(.opacity)
        }
        .padding(12)
        .card(radius: 20)
        .animation(.snappy(duration: 0.25), value: settings.mode)
    }

    @ViewBuilder private var status: some View {
        let (text, color): (String, Color) = {
            if !controller.lastWriteSuccess, controller.statusMessage.hasPrefix("Couldn") {
                return (controller.statusMessage, Palette.alert(scheme))
            }
            switch controller.activeOverride {
            case .boost: return ("Boosting", Palette.amber(scheme))
            case .emergency: return ("Emergency · full speed", Palette.alert(scheme))
            case .hot: return ("Hot · Smart until cooler", Palette.amber(scheme))
            case .none: break
            }
            switch settings.mode {
            case .system: return ("macOS in control", sub)
            case .maximum: return ("Full speed", sub)
            case .manual: return ("Holding speed", Palette.good(scheme))
            case .automatic:
                if let t = hottest, t <= settings.autoThreshold { return ("Below \(Int(settings.autoThreshold))° · resting", Palette.good(scheme)) }
                return (controller.targetSpeed > 0 ? "Target \(controller.targetSpeed.formatted()) RPM" : "Smart", Palette.good(scheme))
            }
        }()
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).lineLimit(1)
    }

    private var smartControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                ForEach(FanPreset.smartCases + [.custom]) { p in profileChip(p) }
            }
            sliderRow("Start at", value: "\(Int(settings.autoThreshold))°",
                      binding: Binding(get: { settings.autoThreshold }, set: { settings.setThreshold($0) }),
                      range: 40...90, step: 1)
            sliderRow("Response", value: responseLabel,
                      binding: Binding(get: { settings.autoAggressiveness }, set: { settings.setResponse($0) }),
                      range: 0...3, step: 0.1)
            sliderRow("Top speed", value: "\(settings.autoMaxSpeed.formatted())",
                      binding: Binding(get: { Double(settings.autoMaxSpeed) }, set: { settings.setTopSpeed(Int($0)) }),
                      range: 2000...6500, step: 100)
        }
    }

    private func profileChip(_ p: FanPreset) -> some View {
        let on = settings.smartProfile == p
        return Button {
            withAnimation(.snappy(duration: 0.25)) { controller.choose(p) }
        } label: {
            Text(p == .performance ? "Perform." : p.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? Color.white : Color.primary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background {
                    if on {
                        Capsule().fill(LinearGradient(colors: Palette.fan, startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .glassEffect(on ? .clear : .regular.interactive(), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(p == .custom ? "Your own start, response and top speed" : "Smart · \(p.rawValue)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sliderRow(_ label: String, value: String, binding: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(sub).frame(width: 62, alignment: .leading)
            Slider(value: binding, in: range, step: step)
                .controlSize(.small)
                .tint(Palette.accent)
            Text(value).font(.system(size: 11, weight: .semibold))
                .frame(width: 68, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .font(.system(size: 11))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(sub)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var responseLabel: String {
        switch settings.autoAggressiveness {
        case ..<0.7: return "Gentle"
        case ..<1.3: return "Quiet"
        case ..<1.9: return "Balanced"
        case ..<2.5: return "Fast"
        default: return "Strongest"
        }
    }

    // MARK: Boost

    private var boostCard: some View {
        let active = controller.boostEndDate != nil
        return HStack(spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 15, weight: .bold))
                .symbolEffect(.pulse, options: .repeating, isActive: active)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(active ? "Boosting" : "Boost").font(.system(size: 15, weight: .bold))
                if let end = controller.boostEndDate {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(countdown(end, now: ctx.date)) left · then \(settings.mode.label)")
                            .font(.system(size: 11)).opacity(0.9).lineLimit(1)
                    }
                } else {
                    Text("10 min at full speed").font(.system(size: 11)).opacity(0.9).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.snappy) { active ? controller.stopBoost() : controller.startBoost() }
            } label: {
                Text(active ? "Stop" : "Start")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x06604F))
                    .padding(.horizontal, 15).frame(height: 30)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .help(active ? "Stop now and go back to your setting" : "Run every fan flat out for 10 minutes. Your setting comes back afterwards.")
        }
        .foregroundStyle(.white)
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: Palette.boost, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(hex: 0x087A67, alpha: 0.28), radius: 10, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
    }

    private func countdown(_ end: Date, now: Date) -> String {
        let s = max(0, Int(end.timeIntervalSince(now)))
        return s >= 60 ? "\(s / 60)m \(String(format: "%02d", s % 60))s" : "\(s)s"
    }

    // MARK: States

    private var setupCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: Palette.fan, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .glassEffect(.regular, in: Circle())
            Text("One quick setup").font(.system(size: 14, weight: .semibold))
            Text("Install the helper so Fan App can set fan speeds without asking for your password each time.")
                .font(.system(size: 11)).foregroundStyle(sub).multilineTextAlignment(.center)
            if let installError {
                Text(installError).font(.system(size: 11)).foregroundStyle(Palette.alert(scheme)).multilineTextAlignment(.center)
            }
            Button("Install helper") {
                installError = nil
                permissions.installHelper { ok, error in
                    if !ok { installError = error ?? "The helper couldn’t be installed." }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .card(radius: 20)
    }

    private func stateCard(symbol: String, colors: [Color], title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .glassEffect(.regular, in: Circle())
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message).font(.system(size: 11)).foregroundStyle(sub).multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .card(radius: 20)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            let fans = viewModel.numberOfFans
            let power = battery.batteryInfo.powerWatts.map { String(format: "%.1f W", $0) }
            Text([fans > 0 ? "\(fans) \(fans == 1 ? "fan" : "fans")" : nil, power].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(sub)
            Spacer()
            if settings.emergencyEnabled {
                Label("Full speed at \(Int(settings.emergencyTemperature))°", systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(sub)
                    .help("Emergency protection: every fan goes to full speed at this temperature")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 4)
    }
}
