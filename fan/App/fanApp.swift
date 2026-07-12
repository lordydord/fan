//
//  ffanApp.swift
//  ffan
//
//  AppDelegate — all UI created on demand, nothing persistent in background.
//

import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarManager: StatusBarManager?
    var viewModel: FanControlViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var displayModeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupApplication()
    }

    private func setupApplication() {
        let viewModel = FanControlViewModel()
        self.viewModel = viewModel

        let statusBarManager = StatusBarManager()
        self.statusBarManager = statusBarManager
        statusBarManager.setupStatusBar()

        let initialMode = UserDefaults.standard.string(forKey: "statusBarDisplayMode") ?? "temperature"
        statusBarManager.setDisplayMode(initialMode)
        configureBatteryMonitoring(for: initialMode)

        displayModeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StatusBarDisplayModeChanged"),
            object: nil, queue: .main
        ) { [weak self, weak statusBarManager] notification in
            if let mode = notification.object as? String {
                statusBarManager?.setDisplayMode(mode)
                self?.configureBatteryMonitoring(for: mode)
            }
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("OpenSettingsWindow"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettingsWindow()
        }

        statusBarManager.setPopoverContentBuilder { [weak self] in
            guard let self = self, let vm = self.viewModel, let sm = self.statusBarManager else {
                return AnyView(EmptyView())
            }
            return AnyView(PopoverView(viewModel: vm, statusBarManager: sm))
        }
        statusBarManager.setQuickActionHandler { [weak viewModel] preset in
            viewModel?.applyPreset(preset)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.initializeMonitoring()
        }
    }

    private func initializeMonitoring() {
        guard let viewModel = viewModel else { return }
        viewModel.startMonitoring()
        Publishers.CombineLatest3(viewModel.$cpuTemperature, viewModel.$gpuTemperature, viewModel.$currentFanSpeed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.updateStatusBarIcon() }
            .store(in: &cancellables)
        BatteryMonitor.shared.$batteryInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusBarIcon() }
            .store(in: &cancellables)
    }

    private func configureBatteryMonitoring(for mode: String) {
        if mode == "power" { BatteryMonitor.shared.startMonitoring() }
        else { BatteryMonitor.shared.stopMonitoring() }
    }

    private func updateStatusBarIcon() {
        guard let viewModel = viewModel, let statusBarManager = statusBarManager else { return }
        let maxTemp = viewModel.getMaxTemperature()
        let fanSpeed = viewModel.currentFanSpeed
        let power = BatteryMonitor.shared.batteryInfo.powerWatts
        statusBarManager.updateIcon(fanSpeed: fanSpeed,
                                    temperature: maxTemp > 0 ? maxTemp : nil,
                                    powerWatts: power)
    }

    func openSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let viewModel = viewModel else { return }
        let hostingView = NSHostingView(rootView:
            SettingsWindowView(isOpen: .constant(true), viewModel: viewModel)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "fan Settings"
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
        BatteryMonitor.shared.stopMonitoring()
        viewModel?.stopMonitoring()
        [displayModeObserver, settingsObserver].compactMap { $0 }.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow?.contentView = nil
            settingsWindow = nil
        }
    }
}

// Minimal SwiftUI App wrapper — Settings scene uses an NSViewRepresentable
// empty placeholder so SwiftUI has no render loop of its own
@main
struct FanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { _NoOpView() }
    }
}

// A true no-op NSView with zero size — gives SwiftUI's Settings scene
// something to host without triggering any layout or render work
private struct _NoOpView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.setFrameSize(.zero)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
