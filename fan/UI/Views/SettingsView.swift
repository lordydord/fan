import SwiftUI
import Charts

enum StatusBarDisplayMode: String, CaseIterable {
    case none = "None"
    case temperature = "Temperature"
    case power = "Power Usage"
    case fanSpeedPercentage = "Fan Speed %"

    var description: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel
    let onBack: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var statusBarDisplayMode = UserDefaults.standard.string(forKey: "statusBarDisplayMode") ?? "temperature"
    @State private var monitoringInterval = UserDefaults.standard.double(forKey: "monitoringInterval") > 0 ? UserDefaults.standard.double(forKey: "monitoringInterval") : 5.0
    @State private var enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
    @State private var highTempAlert = UserDefaults.standard.double(forKey: "highTempAlert") > 0 ? UserDefaults.standard.double(forKey: "highTempAlert") : 85.0
    @State private var autoSwitchMode = UserDefaults.standard.bool(forKey: "autoSwitchMode")

    private let accent = Color(red: 0.91, green: 0.67, blue: 0.25)

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection("General") {
                        settingRow(
                            icon: "power",
                            title: "Launch at login",
                            description: "Start Fan App when you sign in"
                        ) {
                            Toggle("Launch at login", isOn: $launchAtLogin)
                                .labelsHidden()
                                .tint(accent)
                                .onChange(of: launchAtLogin) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
                                    viewModel.launchAtLogin = newValue
                                    LaunchAtLoginManager.shared.isEnabled = newValue
                                }
                        }

                        rowDivider

                        settingRow(
                            icon: "menubar.rectangle",
                            title: "Menu bar display",
                            description: "Reading shown beside the fan icon"
                        ) {
                            Picker("Menu bar display", selection: $statusBarDisplayMode) {
                                ForEach(StatusBarDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.description).tag(modeKey(for: mode))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 132)
                            .onChange(of: statusBarDisplayMode) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "statusBarDisplayMode")
                                viewModel.statusBarDisplayMode = newValue
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("StatusBarDisplayModeChanged"),
                                    object: newValue
                                )
                            }
                        }
                    }

                    settingsSection("Temperature & safety") {
                        settingRow(
                            icon: "timer",
                            title: "Update interval",
                            description: "How often Fan App reads the sensors",
                            layout: .stacked
                        ) {
                            sliderControl(value: $monitoringInterval, range: 2...30, step: 1, valueText: "\(Int(monitoringInterval))s")
                                .onChange(of: monitoringInterval) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "monitoringInterval")
                                    viewModel.setMonitoringInterval(newValue)
                                }
                        }

                        rowDivider

                        settingRow(
                            icon: "thermometer.high",
                            title: "High temperature alert",
                            description: "Warn when the Mac reaches this temperature",
                            layout: .stacked
                        ) {
                            sliderControl(value: $highTempAlert, range: 70...95, step: 1, valueText: "\(Int(highTempAlert))°C")
                                .onChange(of: highTempAlert) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "highTempAlert")
                                }
                        }

                        rowDivider

                        settingRow(
                            icon: "shield.lefthalf.filled",
                            title: "Emergency protection",
                            description: "Run every fan at full speed above this limit",
                            layout: .stacked
                        ) {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Protection")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Toggle("Emergency protection", isOn: Binding(
                                        get: { viewModel.fanController.emergencyProtectionEnabled },
                                        set: {
                                            viewModel.setEmergencyProtection(
                                                enabled: $0,
                                                temperature: viewModel.fanController.emergencyTemperature
                                            )
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(accent)
                                }

                                sliderControl(
                                    value: Binding(
                                        get: { viewModel.fanController.emergencyTemperature },
                                        set: {
                                            viewModel.setEmergencyProtection(
                                                enabled: viewModel.fanController.emergencyProtectionEnabled,
                                                temperature: $0
                                            )
                                        }
                                    ),
                                    range: 80...100,
                                    step: 1,
                                    valueText: "\(Int(viewModel.fanController.emergencyTemperature))°C"
                                )
                            }
                        }
                    }

                    settingsSection("Behaviour") {
                        settingRow(
                            icon: "bell.badge",
                            title: "Notifications",
                            description: "Show an alert when the high limit is reached"
                        ) {
                            Toggle("Notifications", isOn: $enableNotifications)
                                .labelsHidden()
                                .tint(accent)
                                .onChange(of: enableNotifications) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "enableNotifications")
                                }
                        }

                        rowDivider

                        settingRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Automatic switching",
                            description: "Move to smart control when temperatures spike"
                        ) {
                            Toggle("Automatic switching", isOn: $autoSwitchMode)
                                .labelsHidden()
                                .tint(accent)
                                .onChange(of: autoSwitchMode) { _, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "autoSwitchMode")
                                }
                        }
                    }

                    if viewModel.numberOfFans > 1 {
                        settingsSection("Fans") {
                            VStack(spacing: 12) {
                                ForEach(0..<viewModel.numberOfFans, id: \.self) { index in
                                    HStack {
                                        Label("Fan \(index + 1)", systemImage: "fan.fill")
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Stepper(
                                            "\(fanSpeed(at: index)) RPM",
                                            value: Binding(
                                                get: { fanSpeed(at: index) },
                                                set: { viewModel.setFanSpeed($0, fanIndex: index) }
                                            ),
                                            in: 1000...6500,
                                            step: 100
                                        )
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    }
                                }
                            }
                            .padding(14)
                        }
                    }

                    settingsSection("Recent temperature") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Live thermal history")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("°C")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Chart(viewModel.thermalHistory) { sample in
                                AreaMark(
                                    x: .value("Time", sample.date),
                                    y: .value("Temperature", sample.temperature)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [accent.opacity(0.28), accent.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", sample.date),
                                    y: .value("Temperature", sample.temperature)
                                )
                                .foregroundStyle(accent)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            }
                            .chartYScale(domain: 30...105)
                            .chartXAxis(.hidden)
                            .frame(height: 112)
                        }
                        .padding(14)
                    }

                    Button {
                        viewModel.exportDiagnostics()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Export diagnostics")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(.white.opacity(0.32), lineWidth: 0.75)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                        Text("Changes apply immediately")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .frame(width: 380, height: 620)
        .background(background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(SettingsGlassButtonStyle())
            .help("Back to fan controls")

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 34, height: 34)
            .glassEffect(.clear.tint(accent.opacity(0.08)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Fan App")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(-0.5)

            Spacer()

            Text("SETTINGS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var background: some View {
        ZStack {
            Color.clear
            LinearGradient(
                colors: [accent.opacity(0.045), .clear, Color.primary.opacity(0.015)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(accent.opacity(0.035))
                .frame(width: 250, height: 250)
                .blur(radius: 52)
                .offset(x: 150, y: -250)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .liquidGlass(cornerRadius: 17, tint: accent.opacity(0.012), shadowOpacity: 0.04)
        }
    }

    private enum RowLayout { case inline, stacked }

    private func settingRow<Content: View>(
        icon: String,
        title: String,
        description: String,
        layout: RowLayout = .inline,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: layout == .stacked ? 11 : 0) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .glassEffect(.clear.tint(accent.opacity(0.12)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if layout == .inline {
                    content()
                }
            }

            if layout == .stacked {
                content()
                    .padding(.leading, 39)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 53)
    }

    private func sliderControl(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step)
                .tint(accent)
            Text(valueText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func modeKey(for mode: StatusBarDisplayMode) -> String {
        switch mode {
        case .none: return "none"
        case .temperature: return "temperature"
        case .power: return "power"
        case .fanSpeedPercentage: return "fanSpeedPercentage"
        }
    }

    private func fanSpeed(at index: Int) -> Int {
        viewModel.fanSpeeds.indices.contains(index) ? viewModel.fanSpeeds[index] : 1000
    }
}

private struct SettingsGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.68 : 0.82))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                Color.white.opacity(configuration.isPressed ? 0.04 : 0.1),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.22 : 0.38), lineWidth: 0.75)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
