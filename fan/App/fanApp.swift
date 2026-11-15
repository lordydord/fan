//
//  fanApp.swift
//  fan
//
//  Menu-bar app: a status item with a popover, nothing else.
//

import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarManager: StatusBarManager?
    var viewModel: FanControlViewModel?
    private var bag = Set<AnyCancellable>()
    private let settings = FanSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let viewModel = FanControlViewModel(settings: settings)
        self.viewModel = viewModel

        let statusBarManager = StatusBarManager()
        self.statusBarManager = statusBarManager
        statusBarManager.setupStatusBar()

        statusBarManager.setPopoverContentBuilder { [weak self] in
            guard let self, let vm = self.viewModel else { return AnyView(EmptyView()) }
            return AnyView(PopoverView(viewModel: vm, settings: self.settings, controller: vm.fanController))
        }
        statusBarManager.setQuickActionHandler { [weak viewModel] preset in
            viewModel?.applyPreset(preset)
        }
        statusBarManager.setSelectedPresetProvider { [weak self] in
            self?.settings.selectedPreset
        }

        settings.$menuBarDisplay
            .removeDuplicates()
            .sink { [weak self, weak statusBarManager] mode in
                statusBarManager?.setDisplayMode(mode.rawValue)
                self?.configureBatteryMonitoring(for: mode)
            }
            .store(in: &bag)

        LaunchAtLoginManager.shared.ensureRegistered(wanted: settings.launchAtLogin)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.initializeMonitoring()
        }
    }

    private func initializeMonitoring() {
        guard let viewModel else { return }
        viewModel.startMonitoring()

        Publishers.CombineLatest3(viewModel.$cpuTemperature, viewModel.$gpuTemperature, viewModel.$currentFanSpeed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.updateStatusBarIcon() }
            .store(in: &bag)

        BatteryMonitor.shared.$batteryInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusBarIcon() }
            .store(in: &bag)
    }

    private func configureBatteryMonitoring(for mode: MenuBarDisplay) {
        if mode == .power { BatteryMonitor.shared.startMonitoring() }
        else { BatteryMonitor.shared.stopMonitoring() }
    }

    private func updateStatusBarIcon() {
        guard let viewModel, let statusBarManager else { return }
        let maxTemp = viewModel.getMaxTemperature()
        statusBarManager.updateIcon(fanSpeed: viewModel.currentFanSpeed,
                                    temperature: maxTemp > 0 ? maxTemp : nil,
                                    powerWatts: BatteryMonitor.shared.batteryInfo.powerWatts)
    }

    func applicationWillTerminate(_ notification: Notification) {
        bag.removeAll()
        BatteryMonitor.shared.stopMonitoring()
        viewModel?.resetToSystemControl()
        viewModel?.stopMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarManager?.showPopover()
        return false
    }
}

@main
struct FanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { _NoOpView() }
    }
}

/// A zero-size view so SwiftUI's Settings scene has something to host without a render loop.
private struct _NoOpView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.setFrameSize(.zero)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
