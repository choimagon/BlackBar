import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let wallpaperService = WallpaperService()
    private let launchAgentManager = LaunchAgentManager()
    private var shouldStartService = true
    private var isTopBarEnabled = false
    private var toggleMenuItem: NSMenuItem?
    private weak var toggleSwitch: NSSwitch?
    private weak var stateLabel: NSTextField?
    private lazy var statusImages = makeStatusImages()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        handleCommandLineIfNeeded()
        if shouldStartService && isTopBarEnabled {
            wallpaperService.start()
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperService.stop()
    }

    @objc
    private func refreshNow(_ sender: Any?) {
        wallpaperService.refresh(force: true)
    }

    @objc
    private func toggleTopBar(_ sender: Any?) {
        isTopBarEnabled.toggle()

        if isTopBarEnabled {
            wallpaperService.start()
        } else {
            wallpaperService.restoreOriginalWallpapers()
            wallpaperService.stop()
        }

        updateToggleAppearance()
    }

    @objc
    private func restoreOriginalWallpapers(_ sender: Any?) {
        isTopBarEnabled = false
        wallpaperService.restoreOriginalWallpapers()
        wallpaperService.stop()
        updateToggleAppearance()
    }

    @objc
    private func toggleLaunchAgent(_ sender: Any?) {
        do {
            if launchAgentManager.isInstalled {
                try launchAgentManager.uninstall()
            } else {
                try launchAgentManager.install()
            }
            rebuildMenu()
        } catch {
            NSLog("Launch agent toggle failed: \(error.localizedDescription)")
        }
    }

    @objc
    private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton(item.button)
        item.button?.toolTip = "BlackBar"
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        configureStatusButton(statusItem?.button)

        let toggleItem = NSMenuItem()
        toggleItem.view = makeToggleView()
        toggleMenuItem = toggleItem
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "q")

        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        updateToggleAppearance()
    }

    private func configureStatusButton(_ button: NSStatusBarButton?) {
        guard let button else { return }

        if let image = isTopBarEnabled ? statusImages.enabled : statusImages.disabled {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
            return
        }

        button.image = nil
        button.title = "BM"
    }

    private func handleCommandLineIfNeeded() {
        let arguments = Set(CommandLine.arguments.dropFirst())

        if arguments.contains("--install-launch-agent") {
            try? launchAgentManager.install()
        }

        if arguments.contains("--uninstall-launch-agent") {
            try? launchAgentManager.uninstall()
        }

        if arguments.contains("--refresh") || arguments.contains("--once") {
            isTopBarEnabled = true
            wallpaperService.refresh(force: true)
        }

        if arguments.contains("--restore") {
            shouldStartService = false
            isTopBarEnabled = false
            wallpaperService.restoreOriginalWallpapers()
            NSApp.terminate(nil)
        }

        if arguments.contains("--once") {
            shouldStartService = false
            NSApp.terminate(nil)
        }
    }

    @objc
    private func switchValueChanged(_ sender: NSSwitch) {
        let shouldEnable = sender.state == .on
        guard shouldEnable != isTopBarEnabled else {
            updateToggleAppearance()
            return
        }
        toggleTopBar(sender)
    }

    private func makeToggleView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 38))

        let titleLabel = NSTextField(labelWithString: "Top Bar")
        titleLabel.frame = NSRect(x: 14, y: 17, width: 70, height: 16)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        let stateLabel = NSTextField(labelWithString: "")
        stateLabel.frame = NSRect(x: 14, y: 4, width: 80, height: 14)
        stateLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        container.addSubview(stateLabel)
        self.stateLabel = stateLabel

        let toggleSwitch = NSSwitch(frame: NSRect(x: 156, y: 8, width: 51, height: 24))
        toggleSwitch.target = self
        toggleSwitch.action = #selector(switchValueChanged(_:))
        container.addSubview(toggleSwitch)
        self.toggleSwitch = toggleSwitch

        return container
    }

    private func updateToggleAppearance() {
        configureStatusButton(statusItem?.button)
        toggleSwitch?.state = isTopBarEnabled ? .on : .off
        stateLabel?.stringValue = isTopBarEnabled ? "ON" : "OFF"
        stateLabel?.textColor = isTopBarEnabled ? .systemGreen : .systemRed
    }

    private func makeStatusImages() -> (disabled: NSImage?, enabled: NSImage?) {
        guard let imageURL = Bundle.main.resourceURL?.appendingPathComponent("image.png"),
              let disabled = NSImage(contentsOf: imageURL) else {
            return (nil, nil)
        }

        return (disabled, tintedStatusImage(from: disabled))
    }

    private func tintedStatusImage(from image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = buffer[index + 3]
            if alpha == 0 {
                continue
            }

            let red = buffer[index]
            let green = buffer[index + 1]
            let blue = buffer[index + 2]
            let isDark = red < 70 && green < 70 && blue < 70

            if isDark {
                buffer[index] = 255
                buffer[index + 1] = 255
                buffer[index + 2] = 255
            }
        }

        guard let outputImage = context.makeImage() else { return nil }
        return NSImage(cgImage: outputImage, size: image.size)
    }
}
