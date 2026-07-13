//
//  StatusBarManager.swift
//  ffan
//
//  Static status bar icon with a persistent popover controller.
//

import AppKit
import SwiftUI
import Combine

class StatusBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var currentFanSpeed: Int = 0
    private var currentTemperature: Double?
    private var currentPowerWatts: Double?
    private var displayMode: String = "temperature"

    // Stored as a closure so the view is created lazily on first open.
    private var popoverContentBuilder: (() -> AnyView)?
    private var quickActionHandler: ((FanPreset) -> Void)?

    func setupStatusBar() {
        DispatchQueue.main.async { [weak self] in
            self?.createStatusItem()
        }
    }

    // Accept a closure that returns a view, rather than a pre-built view
    func setPopoverContentBuilder(_ builder: @escaping () -> AnyView) {
        self.popoverContentBuilder = builder
        popover?.contentViewController = nil
    }

    func setQuickActionHandler(_ handler: @escaping (FanPreset) -> Void) {
        quickActionHandler = handler
    }

    // Legacy convenience — kept so existing call sites compile
    func setPopoverContent<Content: View>(_ content: Content) {
        setPopoverContentBuilder { AnyView(content) }
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        button.image = createFanIcon(size: 16)
        button.image?.isTemplate = true
        button.title = "--°"
        button.imagePosition = .imageLeft
        button.toolTip = "Fan App"

        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover = NSPopover()
        popover?.behavior = .transient
        popover?.contentSize = NSSize(width: 380, height: 500)
    }

    private func createFanIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size/2, y: size/2)
            let bladeLength: CGFloat = size * 0.42

            for i in 0..<3 {
                let angle = CGFloat(i) * 120 * .pi / 180
                let bladePath = NSBezierPath()
                let hubRadius: CGFloat = size * 0.15

                let endX = center.x + cos(angle) * bladeLength
                let endY = center.y + sin(angle) * bladeLength

                let leftAngle = angle - 0.35
                let leftStartX = center.x + cos(leftAngle) * hubRadius
                let leftStartY = center.y + sin(leftAngle) * hubRadius
                let leftEndX = center.x + cos(angle - 0.2) * bladeLength * 0.9
                let leftEndY = center.y + sin(angle - 0.2) * bladeLength * 0.9

                let rightAngle = angle + 0.35
                let rightStartX = center.x + cos(rightAngle) * hubRadius
                let rightStartY = center.y + sin(rightAngle) * hubRadius
                let rightEndX = center.x + cos(angle + 0.15) * bladeLength * 0.95
                let rightEndY = center.y + sin(angle + 0.15) * bladeLength * 0.95

                bladePath.move(to: NSPoint(x: leftStartX, y: leftStartY))
                bladePath.curve(to: NSPoint(x: leftEndX, y: leftEndY),
                               controlPoint1: NSPoint(x: center.x + cos(angle - 0.25) * bladeLength * 0.5,
                                                     y: center.y + sin(angle - 0.25) * bladeLength * 0.5),
                               controlPoint2: NSPoint(x: leftEndX, y: leftEndY))
                bladePath.curve(to: NSPoint(x: rightEndX, y: rightEndY),
                               controlPoint1: NSPoint(x: endX, y: endY),
                               controlPoint2: NSPoint(x: rightEndX, y: rightEndY))
                bladePath.curve(to: NSPoint(x: rightStartX, y: rightStartY),
                               controlPoint1: NSPoint(x: center.x + cos(angle + 0.2) * bladeLength * 0.5,
                                                     y: center.y + sin(angle + 0.2) * bladeLength * 0.5),
                               controlPoint2: NSPoint(x: rightStartX, y: rightStartY))
                bladePath.close()
                NSColor.black.setFill()
                bladePath.fill()
            }

            let hubSize = size * 0.3
            let hubPath = NSBezierPath(ovalIn: NSRect(x: center.x - hubSize/2,
                                                      y: center.y - hubSize/2,
                                                      width: hubSize, height: hubSize))
            NSColor.black.setFill()
            hubPath.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    func updateIcon(fanSpeed: Int, temperature: Double?, powerWatts: Double? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.currentFanSpeed = fanSpeed
            self?.currentTemperature = temperature
            self?.currentPowerWatts = powerWatts
            self?.updateDisplay()
        }
    }

    func setDisplayMode(_ mode: String) {
        DispatchQueue.main.async { [weak self] in
            self?.displayMode = mode
            if let button = self?.statusItem?.button {
                button.imagePosition = mode == "none" ? .imageOnly : .imageLeft
            }
            self?.updateDisplay()
        }
    }

    private func updateDisplay() {
        guard let button = statusItem?.button else { return }
        let text = getDisplayText()
        if text.isEmpty {
            button.title = ""
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular)
            ]
            button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        }
    }

    private func getDisplayText() -> String {
        switch displayMode {
        case "none": return ""
        case "temperature":
            return currentTemperature.map { String(format: "%.0f°", $0) } ?? "--°"
        case "power":
            return currentPowerWatts.map { String(format: "%.1fW", $0) }
                ?? "\(Int((Double(currentFanSpeed) / 6500.0) * 100))%"
        case "fanSpeedPercentage":
            return "\(Int((Double(currentFanSpeed) / 6500.0) * 100))%"
        default:
            return currentTemperature.map { String(format: "%.0f°", $0) } ?? "--°"
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button,
              let popover = popover else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu(from: button)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showQuickMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        for (index, preset) in FanPreset.selectableCases.enumerated() {
            let item = NSMenuItem(title: preset == .maximum ? "Max (100%)" : preset.rawValue,
                                  action: #selector(runQuickAction(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Fan App", action: #selector(openPopoverFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func runQuickAction(_ sender: NSMenuItem) {
        guard FanPreset.selectableCases.indices.contains(sender.tag) else { return }
        quickActionHandler?(FanPreset.selectableCases[sender.tag])
    }

    @objc private func openPopoverFromMenu() {
        showPopover()
    }

    func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        installPopoverContentIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func installPopoverContentIfNeeded() {
        guard let popover,
              popover.contentViewController == nil,
              let builder = popoverContentBuilder else { return }

        let controller = NSHostingController(rootView: builder())
        // Keep NSPopover's preferred size synchronized with SwiftUI as sensor
        // data arrives and profile controls change their intrinsic height.
        controller.sizingOptions = [.preferredContentSize]
        controller.view.layoutSubtreeIfNeeded()
        let fittedHeight = max(320, ceil(controller.view.fittingSize.height))
        controller.preferredContentSize = NSSize(width: 380, height: fittedHeight)
        popover.contentSize = controller.preferredContentSize
        popover.contentViewController = controller
    }

    func closePopover() {
        popover?.performClose(nil)
    }
}
