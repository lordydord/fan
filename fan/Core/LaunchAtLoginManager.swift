//
//  LaunchAtLoginManager.swift
//  fan
//
//  Open at login through SMAppService. The app is ad-hoc signed, so replacing it with a
//  new build can quietly drop the login item; `ensureRegistered` puts it back on launch
//  whenever the user has asked for it.
//

import Foundation
import ServiceManagement
import Combine
import AppKit

final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var registrationStatus: String = "Unknown"
    @Published private(set) var needsApproval = false

    private init() { refresh() }

    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("LaunchAtLogin: \(error)")
            }
            refresh()
        }
    }

    /// Re-registers the login item when the user wants it but macOS has lost it.
    func ensureRegistered(wanted: Bool) {
        refresh()
        guard wanted else { return }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return
        default:
            try? SMAppService.mainApp.register()
            refresh()
        }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        needsApproval = status == .requiresApproval
        switch status {
        case .enabled: registrationStatus = "Enabled"
        case .notRegistered: registrationStatus = "Not registered"
        case .requiresApproval: registrationStatus = "Needs approval in System Settings"
        case .notFound: registrationStatus = "Not found"
        @unknown default: registrationStatus = "Unknown"
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
