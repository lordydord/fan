import SwiftUI
import Charts

enum StatusBarDisplayMode: String, CaseIterable {
    case none = "None"
    case temperature = "Temperature"
    case power = "Power Usage"
    case fanSpeedPercentage = "Fan Speed %"
    
    var description: String {
        self.rawValue
    }
}

// MARK: - Settings Sheet View (for popover)
struct SettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @Environment(\.dismiss) var dismiss
    @State private var launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var statusBarDisplayMode = UserDefaults.standard.string(forKey: "statusBarDisplayMode") ?? "temperature"
    @State private var monitoringInterval = UserDefaults.standard.double(forKey: "monitoringInterval") > 0 ? UserDefaults.standard.double(forKey: "monitoringInterval") : 5.0
    @State private var enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
    @State private var highTempAlert = UserDefaults.standard.double(forKey: "highTempAlert") > 0 ? UserDefaults.standard.double(forKey: "highTempAlert") : 85.0
    @State private var autoSwitchMode = UserDefaults.standard.bool(forKey: "autoSwitchMode")
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("Settings")
                    .font(.system(size: 16, weight: .bold))
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Close Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 12) {
                    settingCardContent
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            
            Divider()
                .padding(.horizontal)
            
            // Footer Info
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Text("Changes apply immediately")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 380, height: 580)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                LinearGradient(
                    colors: [Color.blue.opacity(0.03), Color.purple.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    @ViewBuilder
    private var settingCardContent: some View {
        // Startup Settings
        settingCard(
            icon: "rectangle.and.paperclip",
            title: "Launch at Login",
            description: "Automatically start the app when you log in"
        ) {
            Toggle("", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { oldValue, newValue in
                    UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
                    viewModel.launchAtLogin = newValue
                    updateLaunchAtLogin(newValue)
                }
        }
        
        // Status Bar Display Mode
        settingCard(
            icon: "menubar.rectangle",
            title: "Menu Bar Display",
            description: "What information to show in the status bar"
        ) {
            Picker("", selection: $statusBarDisplayMode) {
                Text("None").tag("none")
                Text("Temperature").tag("temperature")
                Text("Power Usage").tag("power")
                Text("Fan Speed %").tag("fanSpeedPercentage")
            }
            .pickerStyle(.segmented)
            .onChange(of: statusBarDisplayMode) { oldValue, newValue in
                UserDefaults.standard.set(newValue, forKey: "statusBarDisplayMode")
                // Update viewModel and notify status bar manager
                viewModel.statusBarDisplayMode = newValue
                NotificationCenter.default.post(name: NSNotification.Name("StatusBarDisplayModeChanged"), object: newValue)
            }
        }
        
        // Monitoring Interval
        settingCard(
            icon: "timer",
            title: "Monitoring Interval",
            description: "How often to check temperatures (seconds)"
        ) {
            HStack {
                Slider(value: $monitoringInterval, in: 0.5...5.0, step: 0.5)
                Text(String(format: "%.1f", monitoringInterval) + "s")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            .onChange(of: monitoringInterval) { oldValue, newValue in
                UserDefaults.standard.set(newValue, forKey: "monitoringInterval")
            }
        }
        
        // High Temperature Alert
        settingCard(
            icon: "exclamationmark.triangle.fill",
            title: "High Temp Alert",
            description: "Alert threshold temperature (°C)"
        ) {
            HStack {
                Slider(value: $highTempAlert, in: 70...95, step: 1)
                Text(String(format: "%.0f", highTempAlert) + "°")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
            .onChange(of: highTempAlert) { oldValue, newValue in
                UserDefaults.standard.set(newValue, forKey: "highTempAlert")
            }
        }
        
        // Enable Notifications
        settingCard(
            icon: "bell.fill",
            title: "Notifications",
            description: "Show alerts for high temperature events"
        ) {
            Toggle("", isOn: $enableNotifications)
                .onChange(of: enableNotifications) { oldValue, newValue in
                    UserDefaults.standard.set(newValue, forKey: "enableNotifications")
                }
        }
        
        // Auto Switch Mode
        settingCard(
            icon: "arrow.left.arrow.right",
            title: "Auto Mode Switching",
            description: "Switch to automatic mode on high temps"
        ) {
            Toggle("", isOn: $autoSwitchMode)
                .onChange(of: autoSwitchMode) { oldValue, newValue in
                    UserDefaults.standard.set(newValue, forKey: "autoSwitchMode")
                }
        }
        
        Spacer()
            .frame(height: 8)
    }
    
    @ViewBuilder
    private func settingCard<Content: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue.opacity(0.8))
                    .frame(width: 24, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
            }
            
            content()
                .padding(.leading, 34)
        }
        .padding(12)
        .liquidGlass()
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLoginManager.shared.isEnabled = enabled
    }
}

// MARK: - Settings Window View (for separate macOS window)
struct SettingsWindowView: View {
    @Binding var isOpen: Bool
    @ObservedObject var viewModel: FanControlViewModel
    @State private var launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    @State private var statusBarDisplayMode = UserDefaults.standard.string(forKey: "statusBarDisplayMode") ?? "temperature"
    @State private var monitoringInterval = UserDefaults.standard.double(forKey: "monitoringInterval") > 0 ? UserDefaults.standard.double(forKey: "monitoringInterval") : 5.0
    @State private var enableNotifications = UserDefaults.standard.bool(forKey: "enableNotifications")
    @State private var highTempAlert = UserDefaults.standard.double(forKey: "highTempAlert") > 0 ? UserDefaults.standard.double(forKey: "highTempAlert") : 85.0
    @State private var autoSwitchMode = UserDefaults.standard.bool(forKey: "autoSwitchMode")
    
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Title and Close Button
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("fan Settings")
                            .font(.system(size: 18, weight: .bold))
                        Text("Customize your fan control experience")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        NSApplication.shared.windows.first(where: { $0.title == "fan Settings" })?.close()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Close (Cmd+W)")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                
                Divider()
                    .padding(.horizontal)
                
                // Settings Content
                ScrollView {
                    VStack(spacing: 14) {
                        settingWindowCard(
                            icon: "rectangle.and.paperclip",
                            title: "Launch at Login",
                            description: "Automatically start the app when you log in"
                        ) {
                            Toggle("", isOn: $launchAtLogin)
                                .onChange(of: launchAtLogin) { oldValue, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
                                    viewModel.launchAtLogin = newValue
                                    LaunchAtLoginManager.shared.isEnabled = newValue
                                }
                        }
                        
                        settingWindowCard(
                            icon: "menubar.rectangle",
                            title: "Menu Bar Display",
                            description: "What information to show in the menu bar"
                        ) {
                            Picker("", selection: $statusBarDisplayMode) {
                                Text("None").tag("none")
                                Text("Temperature").tag("temperature")
                                Text("Power Usage").tag("power")
                                Text("Fan Speed %").tag("fanSpeedPercentage")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: statusBarDisplayMode) { oldValue, newValue in
                                UserDefaults.standard.set(newValue, forKey: "statusBarDisplayMode")
                                viewModel.statusBarDisplayMode = newValue
                                // Notify status bar manager to update display
                                NotificationCenter.default.post(name: NSNotification.Name("StatusBarDisplayModeChanged"), object: newValue)
                            }
                        }
                        
                        settingWindowCard(
                            icon: "timer",
                            title: "Monitoring Interval",
                            description: "How often to check temperatures (seconds)"
                        ) {
                            HStack {
                                Slider(value: $monitoringInterval, in: 2...30, step: 1)
                                Text(String(format: "%.1f", monitoringInterval) + "s")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45)
                            }
                            .onChange(of: monitoringInterval) { oldValue, newValue in
                                UserDefaults.standard.set(newValue, forKey: "monitoringInterval")
                                viewModel.setMonitoringInterval(newValue)
                            }
                        }
                        
                        settingWindowCard(
                            icon: "exclamationmark.triangle.fill",
                            title: "High Temp Alert Threshold",
                            description: "Temperature that triggers warnings (°C)"
                        ) {
                            HStack {
                                Slider(value: $highTempAlert, in: 70...95, step: 1)
                                Text(String(format: "%.0f", highTempAlert) + "°C")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 50)
                            }
                            .onChange(of: highTempAlert) { oldValue, newValue in
                                UserDefaults.standard.set(newValue, forKey: "highTempAlert")
                            }
                        }
                        
                        settingWindowCard(
                            icon: "bell.fill",
                            title: "Notifications",
                            description: "Show system alerts for high temperature events"
                        ) {
                            Toggle("", isOn: $enableNotifications)
                                .onChange(of: enableNotifications) { oldValue, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "enableNotifications")
                                }
                        }
                        
                        settingWindowCard(
                            icon: "arrow.left.arrow.right",
                            title: "Auto Mode Switching",
                            description: "Automatically switch to auto control when temps spike"
                        ) {
                            Toggle("", isOn: $autoSwitchMode)
                                .onChange(of: autoSwitchMode) { oldValue, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "autoSwitchMode")
                                }
                        }

                        settingWindowCard(
                            icon: "shield.checkered",
                            title: "Emergency Protection",
                            description: "Force all fans to 100% at the selected temperature"
                        ) {
                            VStack(spacing: 8) {
                                Toggle("Enabled", isOn: Binding(
                                    get: { viewModel.fanController.emergencyProtectionEnabled },
                                    set: { viewModel.setEmergencyProtection(enabled: $0, temperature: viewModel.fanController.emergencyTemperature) }
                                ))
                                HStack {
                                    Slider(value: Binding(
                                        get: { viewModel.fanController.emergencyTemperature },
                                        set: { viewModel.setEmergencyProtection(enabled: viewModel.fanController.emergencyProtectionEnabled, temperature: $0) }
                                    ), in: 80...100, step: 1)
                                    Text("\(Int(viewModel.fanController.emergencyTemperature))°C")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                }
                            }
                        }

                        if viewModel.numberOfFans > 1 {
                            settingWindowCard(
                                icon: "fan",
                                title: "Per-Fan Control",
                                description: "Adjust each detected fan independently"
                            ) {
                                VStack(spacing: 8) {
                                    ForEach(0..<viewModel.numberOfFans, id: \.self) { index in
                                        Stepper("Fan \(index + 1): \(viewModel.fanSpeeds.indices.contains(index) ? viewModel.fanSpeeds[index] : 0) RPM", value: Binding(
                                            get: { viewModel.fanSpeeds.indices.contains(index) ? viewModel.fanSpeeds[index] : 1000 },
                                            set: { viewModel.setFanSpeed($0, fanIndex: index) }
                                        ), in: 1000...6500, step: 100)
                                    }
                                }
                            }
                        }

                        settingWindowCard(
                            icon: "chart.xyaxis.line",
                            title: "Recent Thermal History",
                            description: "Recent temperature readings while the app is running"
                        ) {
                            Chart(viewModel.thermalHistory) { sample in
                                LineMark(x: .value("Time", sample.date), y: .value("Temperature", sample.temperature))
                                    .foregroundStyle(.orange)
                            }
                            .chartYScale(domain: 30...105)
                            .frame(height: 120)
                        }

                        settingWindowCard(
                            icon: "doc.text.magnifyingglass",
                            title: "Diagnostics",
                            description: "Save sensor, helper and control details for troubleshooting"
                        ) {
                            Button("Export Diagnostics…") { viewModel.exportDiagnostics() }
                        }
                        
                        Spacer()
                            .frame(height: 8)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                }
                
                Divider()
                    .padding(.horizontal)
                
                // Footer Info
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    Text("All changes apply immediately without restarting the app")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 450, minHeight: 620)
        .onAppear {
            if let window = NSApplication.shared.windows.first(where: { $0.title == "fan Settings" }) {
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
    
    @ViewBuilder
    private func settingWindowCard<Content: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue.opacity(0.8))
                    .frame(width: 28, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
            }
            
            content()
                .padding(.leading, 40)
        }
        .padding(14)
        .liquidGlass()
    }
}
