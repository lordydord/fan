//
//  SettingsView.swift
//  fan
//
//  Settings page inside the popover, laid out like Claude Usage's. Every control binds
//  straight to FanSettings, which saves on change, so what you see is what is stored.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var settings: FanSettings
    @ObservedObject private var login = LaunchAtLoginManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared
    let back: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var sub: Color { Palette.sub(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundIconButton(symbol: "chevron.left", label: "Back", action: back)
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .frame(height: 28)

            section("Menu bar") {
                row("Show") {
                    Picker("Show", selection: $settings.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 196)
                }
            }

            section("When it gets hot") {
                sliderRow("Hot at", value: "\(Int(settings.highTempAlert))°",
                          binding: $settings.highTempAlert, range: 70...95)
                toggle("Notify me", $settings.notifyHighTemp)
                toggle("Switch to Smart until it cools", $settings.autoSwitchWhenHot,
                       help: "Only in macOS or Manual mode. Your choice comes back once it’s 5° cooler — it isn’t changed.")
            }

            section("Safety") {
                toggle("Full speed in an emergency", $settings.emergencyEnabled)
                sliderRow("Above", value: "\(Int(settings.emergencyTemperature))°",
                          binding: $settings.emergencyTemperature, range: 80...100)
                    .disabled(!settings.emergencyEnabled)
                    .opacity(settings.emergencyEnabled ? 1 : 0.45)
            }

            section("General") {
                row("Read sensors every") {
                    Picker("Read sensors every", selection: $settings.monitoringInterval) {
                        ForEach(FanSettings.intervals, id: \.self) { Text("\(Int($0))s").tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                toggle("Open at login", Binding(
                    get: { settings.launchAtLogin },
                    set: { on in
                        settings.launchAtLogin = on
                        login.isEnabled = on
                    }))
                if settings.launchAtLogin && login.needsApproval {
                    row("Needs approval in System Settings") {
                        Button("Open…") { login.openLoginItemsSettings() }.controlSize(.small)
                    }
                    .foregroundStyle(Palette.amber(scheme))
                }
                row("Diagnostics") {
                    Button("Export…") { viewModel.exportDiagnostics() }.controlSize(.small)
                }
            }

            HStack {
                Image(systemName: permissions.isHelperInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(permissions.isHelperInstalled ? Palette.good(scheme) : Palette.amber(scheme))
                Text(permissions.isHelperInstalled ? "Settings save as you go" : "Helper not installed")
                    .foregroundStyle(sub)
                Spacer()
                Button {
                    viewModel.resetToSystemControl()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
                } label: {
                    Text("Quit").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(scheme == .dark ? Color(hex: 0xFF7FA3) : Color(hex: 0xB0123F))
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(Capsule().fill(Color(hex: 0xC8174D, alpha: 0.12)))
                }
                .buttonStyle(.plain)
                .help("Hands the fans back to macOS, then quits")
            }
            .font(.system(size: 11))
            .padding(.horizontal, 4)
        }
        .onAppear { login.refresh() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title).padding(.leading, 2)
            VStack(spacing: 6) { content() }
                .padding(10)
                .card(radius: 16)
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 26)
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>, help: String? = nil) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Toggle(label, isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Palette.accent)
        }
        .frame(minHeight: 26)
        .help(help ?? "")
    }

    private func sliderRow(_ label: String, value: String, binding: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 52, alignment: .leading)
            Slider(value: binding, in: range, step: 1)
                .controlSize(.small)
                .tint(Palette.accent)
            Text(value).font(.system(size: 11, weight: .semibold))
                .frame(width: 34, alignment: .trailing)
        }
        .frame(minHeight: 26)
    }
}
