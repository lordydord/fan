import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var battery = BatteryMonitor.shared
    var statusBarManager: StatusBarManager?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingQuitConfirm = false
    @State private var showingSettings = false
    @State private var installError: String?

    private let accent = Color(red: 0.91, green: 0.67, blue: 0.25)

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(viewModel: viewModel) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        showingSettings = false
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    header

                    if !permissions.isHelperInstalled {
                        setupState
                    } else if !viewModel.hasAccess {
                        accessState
                    } else if viewModel.cpuTemperature == nil {
                        loadingState
                    } else {
                        dashboard
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(background)
        .onAppear {
            if !viewModel.isMonitoring { viewModel.startMonitoring() }
            battery.startMonitoring()
        }
        .onDisappear {
            if viewModel.statusBarDisplayMode != "power" { battery.stopMonitoring() }
        }
        .alert("Quit Fan App?", isPresented: $showingQuitConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Quit", role: .destructive) { quitApp() }
        } message: {
            Text("System fan control will be restored before the app closes.")
        }
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [accent.opacity(0.09), .clear, Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(temperatureColor.opacity(0.08))
                .frame(width: 240, height: 240)
                .blur(radius: 48)
                .offset(x: 145, y: -210)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent)
                Image(systemName: "fan.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .rotationEffect(.degrees(viewModel.currentFanSpeed > 0 ? 12 : 0))
                    .animation(reduceMotion ? nil : .spring(response: 0.45), value: viewModel.currentFanSpeed)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Fan App")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showingSettings = true
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ChromeButtonStyle())
            .help("Settings")

            Button { showingQuitConfirm = true } label: {
                Image(systemName: "power")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(ChromeButtonStyle())
            .help("Quit Fan App")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var dashboard: some View {
        VStack(spacing: 14) {
            hero
            presetStrip
            controlPanel
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                TemperatureDial(
                    temperature: viewModel.cpuTemperature,
                    color: temperatureColor,
                    status: temperatureStatus
                )

                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FAN SPEED")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.25)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(viewModel.currentFanSpeed.formatted())
                                .font(.system(size: 29, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("RPM")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    FanBar(progress: fanProgress, accent: accent)

                    HStack(spacing: 8) {
                        MetricChip(icon: "bolt.fill", value: powerText, label: "power")
                        MetricChip(icon: "fan.fill", value: "\(viewModel.numberOfFans)", label: viewModel.numberOfFans == 1 ? "fan" : "fans")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.primary.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                }
        }
    }

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("PROFILE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.25)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(profileDescription)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                ForEach(FanPreset.selectableCases) { preset in
                    PresetButton(
                        preset: preset,
                        isSelected: viewModel.activePreset == preset,
                        accent: accent
                    ) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.applyPreset(preset)
                        }
                    }
                }
            }
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.controlMode == .automatic ? "Smart control" : "Manual control")
                        .font(.system(size: 13, weight: .semibold))
                    Text(viewModel.controlMode == .automatic ? "Responds to heat automatically" : "Hold one fixed fan speed")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: Binding(
                    get: { viewModel.controlMode },
                    set: { viewModel.setControlMode($0) }
                )) {
                    Text("Manual").tag(ControlMode.manual)
                    Text("Smart").tag(ControlMode.automatic)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 126)
            }

            if viewModel.controlMode == .automatic {
                autoControls
            } else {
                manualControls
            }

            HStack(spacing: 10) {
                if viewModel.boostEndDate == nil {
                    Button { viewModel.startBoost() } label: {
                        Label("10 min boost", systemImage: "wind")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentButtonStyle(accent: accent))
                } else {
                    Button { viewModel.stopBoost() } label: {
                        Label("Stop boost", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentButtonStyle(accent: accent))
                }

                Button { viewModel.applyPreset(.system) } label: {
                    Label("Give back to macOS", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(15)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var manualControls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Target speed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.manualSpeed.formatted()) RPM")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.manualSpeed) },
                    set: { viewModel.setManualSpeed(Int($0)) }
                ),
                in: 1_000...6_500,
                step: 100
            )
            .tint(accent)
        }
    }

    private var autoControls: some View {
        HStack(spacing: 10) {
            CompactControl(
                label: "START COOLING",
                value: String(format: "%.0f°", viewModel.autoThreshold),
                icon: "thermometer.medium",
                accent: accent
            ) {
                Slider(
                    value: Binding(
                        get: { viewModel.autoThreshold },
                        set: { viewModel.setAutoThreshold($0) }
                    ),
                    in: 40...90,
                    step: 5
                )
                .tint(accent)
            }

            CompactControl(
                label: "RESPONSE",
                value: responseLabel,
                icon: "dial.medium",
                accent: accent
            ) {
                Slider(
                    value: Binding(
                        get: { viewModel.autoAggressiveness },
                        set: { viewModel.setAutoAggressiveness($0) }
                    ),
                    in: 0...3,
                    step: 0.1
                )
                .tint(accent)
            }
        }
    }

    private var setupState: some View {
        StatePanel(
            icon: "wrench.and.screwdriver.fill",
            title: "One quick setup",
            message: "Install the helper so fan can safely adjust cooling without asking for your password each time.",
            accent: accent,
            error: installError,
            actionTitle: "Install helper"
        ) {
            installError = nil
            permissions.installHelper { success, error in
                if !success { installError = error ?? "The helper could not be installed." }
            }
        }
    }

    private var accessState: some View {
        StatePanel(
            icon: "lock.trianglebadge.exclamationmark.fill",
            title: "System access needed",
            message: viewModel.lastError ?? "fan cannot read the Mac's thermal sensors yet.",
            accent: .orange,
            error: nil,
            actionTitle: nil,
            action: nil
        )
    }

    private var loadingState: some View {
        StatePanel(
            icon: "waveform.path.ecg",
            title: "Reading your Mac",
            message: "The first thermal reading can take a moment.",
            accent: accent,
            error: nil,
            actionTitle: nil,
            action: nil
        )
    }

    private var temperatureColor: Color {
        guard let temp = viewModel.cpuTemperature else { return .secondary }
        if temp < 55 { return Color(red: 0.35, green: 0.72, blue: 0.67) }
        if temp < 75 { return accent }
        return Color(red: 0.91, green: 0.38, blue: 0.29)
    }

    private var temperatureStatus: String {
        guard let temp = viewModel.cpuTemperature else { return "Reading" }
        if temp < 55 { return "Cool" }
        if temp < 75 { return "Comfortable" }
        if temp < 88 { return "Running warm" }
        return "High heat"
    }

    private var headerSubtitle: String {
        viewModel.controlMode == .automatic ? "Smart cooling active" : "Manual cooling active"
    }

    private var fanProgress: Double {
        max(0, min(1, Double(viewModel.currentFanSpeed - 1_000) / 5_500))
    }

    private var powerText: String {
        battery.batteryInfo.powerWatts.map { String(format: "%.1fW", $0) } ?? "--W"
    }

    private var profileDescription: String {
        switch viewModel.activePreset {
        case .system: return "macOS decides"
        case .quiet: return "lower noise"
        case .balanced: return "everyday cooling"
        case .performance: return "earlier response"
        case .maximum: return "full speed"
        case .custom: return "custom settings"
        }
    }

    private var responseLabel: String {
        switch viewModel.autoAggressiveness {
        case ..<0.7: return "Gentle"
        case ..<1.3: return "Quiet"
        case ..<1.9: return "Balanced"
        case ..<2.5: return "Fast"
        default: return "Maximum"
        }
    }

    private func quitApp() {
        viewModel.resetToSystemControl()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct TemperatureDial: View {
    let temperature: Double?
    let color: Color
    let status: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard let temperature else { return 0 }
        return max(0.05, min(1, (temperature - 30) / 70))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.25), radius: 7)

            VStack(spacing: 1) {
                HStack(alignment: .top, spacing: 0) {
                    Text(temperature.map { String(format: "%.0f", $0) } ?? "--")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-1.5)
                        .monospacedDigit()
                    Text("°")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .padding(.top, 4)
                }
                Text(status)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 122, height: 122)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress)
    }
}

private struct FanBar: View {
    let progress: Double
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(accent)
                    .frame(width: max(5, proxy.size.width * progress))
            }
        }
        .frame(height: 5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress)
    }
}

private struct MetricChip: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PresetButton: View {
    let preset: FanPreset
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    private var symbol: String {
        switch preset {
        case .system: return "apple.logo"
        case .quiet: return "leaf.fill"
        case .balanced: return "circle.lefthalf.filled"
        case .performance: return "bolt.fill"
        case .maximum: return "wind"
        case .custom: return "slider.horizontal.3"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(preset.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.black.opacity(0.82) : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                isSelected ? accent : Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct CompactControl<Content: View>: View {
    let label: String
    let value: String
    let icon: String
    let accent: Color
    @ViewBuilder let content: Content

    init(label: String, value: String, icon: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.label = label
        self.value = value
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                Text(label).font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct StatePanel: View {
    let icon: String
    let title: String
    let message: String
    let accent: Color
    let error: String?
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 58, height: 58)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 5) {
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            if let error {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AccentButtonStyle(accent: accent))
                    .frame(width: 170)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
    }
}

private struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.11 : 0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AccentButtonStyle: ButtonStyle {
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    PopoverView(viewModel: FanControlViewModel())
}
