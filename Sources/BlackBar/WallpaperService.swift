import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class WallpaperService {
    private static let refreshInterval: TimeInterval = 1.0

    private let workspace = NSWorkspace.shared
    private let stateStore = WallpaperStateStore()
    private let renderer = WallpaperRenderer()
    private let liveCapture = LiveDesktopCapture()
    private let fileManager = FileManager.default

    private var states: [String: ScreenWallpaperState] = [:]
    private var refreshTimer: Timer?
    private var observers: [NotificationObserver] = []
    private var isRefreshing = false
    private var isRunning = false

    func start() {
        guard !isRunning else {
            refresh(force: false)
            return
        }

        isRunning = true
        states = stateStore.load()
        installObservers()
        refresh(force: false)
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh(force: false)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    func refresh(force: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            stateStore.save(states)
        }

        for screen in NSScreen.screens {
            autoreleasepool {
                process(screen: screen, force: force)
            }
        }
    }

    func restoreOriginalWallpapers() {
        states = stateStore.load()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let screenID = String(displayID)
            guard let state = states[screenID] else { continue }

            let options = workspace.desktopImageOptions(for: screen) ?? [:]
            let restoreURL = state.restoreSnapshotURL ?? state.originalURL
            do {
                try workspace.setDesktopImageURL(restoreURL, for: screen, options: options)
            } catch {
                NSLog("Wallpaper restore failed for display \(screenID): \(error.localizedDescription)")
            }
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(
            NotificationObserver(
                center: center,
                token: center.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.refresh(force: true)
                }
            )
        )

        observers.append(
            NotificationObserver(
                center: workspace.notificationCenter,
                token: workspace.notificationCenter.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.refresh(force: false)
                }
            )
        )

        observers.append(
            NotificationObserver(
                center: workspace.notificationCenter,
                token: workspace.notificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.refresh(force: false)
                }
            )
        )
    }

    private func process(screen: NSScreen, force: Bool) {
        guard let displayID = screen.displayID else { return }
        let screenID = String(displayID)

        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let state = states[screenID]
        let currentURL = workspace.desktopImageURL(for: screen)
        let sourceURL = resolveSourceURL(currentURL: currentURL, state: state)

        guard let sourceURL else { return }
        guard let descriptor = makeDescriptor(
            for: screen,
            sourceURL: sourceURL,
            options: options
        ) else { return }

        if !force,
           let state,
           state.descriptor == descriptor,
           currentURL?.standardizedFileURL == state.generatedURL.standardizedFileURL,
           fileManager.fileExists(atPath: state.generatedURL.path) {
            return
        }

        do {
            let liveImage = liveCapture.captureBackground(for: screen)
            let restoreSnapshotURL = try makeRestoreSnapshotIfNeeded(
                screenID: screenID,
                currentURL: currentURL,
                existingState: state,
                liveImage: liveImage,
                descriptor: descriptor
            )
            let generatedURL = try renderer.render(
                for: descriptor,
                liveImage: liveImage
            )
            try workspace.setDesktopImageURL(generatedURL, for: screen, options: options)
            states[screenID] = ScreenWallpaperState(
                descriptor: descriptor,
                originalURL: sourceURL,
                generatedURL: generatedURL,
                restoreSnapshotURL: restoreSnapshotURL
            )
        } catch {
            NSLog("Wallpaper update failed for display \(screenID): \(error.localizedDescription)")
        }
    }

    private func makeRestoreSnapshotIfNeeded(
        screenID: String,
        currentURL: URL?,
        existingState: ScreenWallpaperState?,
        liveImage: CGImage?,
        descriptor: WallpaperDescriptor
    ) throws -> URL? {
        if let currentURL, renderer.isManagedWallpaper(currentURL) {
            return existingState?.restoreSnapshotURL
        }

        guard let liveImage else {
            return existingState?.restoreSnapshotURL
        }

        return try renderer.writeRestoreSnapshot(
            liveImage: liveImage,
            screenID: screenID,
            descriptor: descriptor
        )
    }

    private func resolveSourceURL(currentURL: URL?, state: ScreenWallpaperState?) -> URL? {
        guard let currentURL else {
            return state?.originalURL
        }

        if renderer.isManagedWallpaper(currentURL) {
            return state?.originalURL
        }

        return currentURL
    }

    private func makeDescriptor(
        for screen: NSScreen,
        sourceURL: URL,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) -> WallpaperDescriptor? {
        let pixelSize = screen.pixelSize
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let maskHeightPoints = screen.maskHeightPoints
        let scale = screen.backingScaleFactor
        let maskHeightPixels = Int(ceil(maskHeightPoints * scale))

        let resourceValues = try? sourceURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let fileSize = resourceValues?.fileSize ?? 0
        let modifiedAt = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0

        let scalingRawValue = (options[.imageScaling] as? NSNumber).map { UInt($0.intValue) }
            ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue

        return WallpaperDescriptor(
            sourceURL: sourceURL.standardizedFileURL,
            canvasWidth: pixelSize.width,
            canvasHeight: pixelSize.height,
            maskHeight: maskHeightPixels,
            imageScalingRawValue: scalingRawValue,
            sourceFileSize: fileSize,
            sourceModifiedAt: modifiedAt
        )
    }
}

private struct NotificationObserver {
    let center: NotificationCenter
    let token: NSObjectProtocol
}

private final class WallpaperRenderer {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        cacheDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent("BlackBar")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func render(for descriptor: WallpaperDescriptor, liveImage: CGImage?) throws -> URL {
        let outputURL = cacheDirectory.appendingPathComponent("\(descriptor.cacheKey).png")
        let image = try loadImage(for: descriptor, liveImage: liveImage)

        guard let context = CGContext(
            data: nil,
            width: descriptor.canvasWidth,
            height: descriptor.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw WallpaperError.contextFailed
        }

        let canvas = CGRect(
            x: 0,
            y: 0,
            width: descriptor.canvasWidth,
            height: descriptor.canvasHeight
        )

        context.interpolationQuality = .high
        context.setFillColor(NSColor.black.cgColor)
        context.fill(canvas)
        context.draw(image, in: drawRect(for: image, canvas: canvas, scaling: descriptor.imageScaling))
        context.fill(CGRect(
            x: 0,
            y: descriptor.canvasHeight - descriptor.maskHeight,
            width: descriptor.canvasWidth,
            height: descriptor.maskHeight
        ))

        guard let outputImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw WallpaperError.outputFailed(outputURL.path)
        }

        CGImageDestinationAddImage(destination, outputImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw WallpaperError.outputFailed(outputURL.path)
        }

        return outputURL
    }

    func writeRestoreSnapshot(
        liveImage: CGImage,
        screenID: String,
        descriptor: WallpaperDescriptor
    ) throws -> URL {
        let outputURL = cacheDirectory.appendingPathComponent(
            "restore_\(screenID)_\(descriptor.canvasWidth)x\(descriptor.canvasHeight).png"
        )
        try write(image: liveImage, to: outputURL)
        return outputURL
    }

    private func loadImage(for descriptor: WallpaperDescriptor, liveImage: CGImage?) throws -> CGImage {
        if let liveImage {
            return liveImage
        }

        guard let source = CGImageSourceCreateWithURL(descriptor.sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw WallpaperError.loadFailed(descriptor.sourceURL.path)
        }

        return image
    }

    private func write(image: CGImage, to outputURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw WallpaperError.outputFailed(outputURL.path)
        }

        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            throw WallpaperError.outputFailed(outputURL.path)
        }
    }

    func isManagedWallpaper(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(cacheDirectory.path)
    }

    private func drawRect(for image: CGImage, canvas: CGRect, scaling: NSImageScaling) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        let canvasSize = canvas.size

        switch scaling {
        case .scaleAxesIndependently:
            return canvas
        case .scaleProportionallyDown:
            return aspectFitRect(imageSize: imageSize, canvasSize: canvasSize)
        default:
            return aspectFillRect(imageSize: imageSize, canvasSize: canvasSize)
        }
    }

    private func aspectFillRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (canvasSize.width - width) * 0.5
        let y = (canvasSize.height - height) * 0.5
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func aspectFitRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (canvasSize.width - width) * 0.5
        let y = (canvasSize.height - height) * 0.5
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private final class LiveDesktopCapture {
    private let wallpaperOwner = "Dock"
    private let wallpaperPrefix = "Wallpaper-"

    func captureBackground(for screen: NSScreen) -> CGImage? {
        guard let displayID = screen.displayID else { return nil }
        guard let wallpaperWindowID = wallpaperWindowID(for: displayID) else { return nil }

        return CGWindowListCreateImage(
            CGRect.null,
            .optionIncludingWindow,
            wallpaperWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    private func wallpaperWindowID(for displayID: CGDirectDisplayID) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID).integral

        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  ownerName == wallpaperOwner,
                  let windowID = window[kCGWindowNumber as String] as? UInt32,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary)?.integral else {
                continue
            }

            let windowName = window[kCGWindowName as String] as? String
            let isWallpaperWindow = windowName?.hasPrefix(wallpaperPrefix) == true
                || (windowName == nil && bounds == displayBounds)

            if isWallpaperWindow && bounds == displayBounds {
                return CGWindowID(windowID)
            }
        }

        return nil
    }
}

private enum WallpaperError: Error {
    case loadFailed(String)
    case contextFailed
    case outputFailed(String)
}

private struct WallpaperDescriptor: Codable, Equatable {
    let sourceURL: URL
    let canvasWidth: Int
    let canvasHeight: Int
    let maskHeight: Int
    let imageScalingRawValue: UInt
    let sourceFileSize: Int
    let sourceModifiedAt: TimeInterval

    var imageScaling: NSImageScaling {
        NSImageScaling(rawValue: imageScalingRawValue) ?? .scaleProportionallyUpOrDown
    }

    var cacheKey: String {
        let source = sourceURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(source)_\(canvasWidth)x\(canvasHeight)_\(maskHeight)_\(imageScalingRawValue)_\(sourceFileSize)_\(Int(sourceModifiedAt))"
    }
}

private struct ScreenWallpaperState: Codable {
    let descriptor: WallpaperDescriptor
    let originalURL: URL
    let generatedURL: URL
    let restoreSnapshotURL: URL?
}

private struct WallpaperStateStore {
    private let fileManager = FileManager.default

    private var stateURL: URL {
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("BlackBar")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }

    func load() -> [String: ScreenWallpaperState] {
        guard let data = try? Data(contentsOf: stateURL) else { return [:] }
        return (try? JSONDecoder().decode([String: ScreenWallpaperState].self, from: data)) ?? [:]
    }

    func save(_ states: [String: ScreenWallpaperState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var pixelSize: (width: Int, height: Int) {
        let scale = backingScaleFactor
        return (
            width: Int(round(frame.width * scale)),
            height: Int(round(frame.height * scale))
        )
    }

    var maskHeightPoints: CGFloat {
        let menuBarHeight = max(0, frame.maxY - visibleFrame.maxY)
        if #available(macOS 12.0, *) {
            return max(menuBarHeight, safeAreaInsets.top)
        }
        return menuBarHeight
    }
}
