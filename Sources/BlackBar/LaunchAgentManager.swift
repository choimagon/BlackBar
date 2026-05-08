import Foundation

struct LaunchAgentManager {
    private let fileManager = FileManager.default
    private let identifier = "com.blackbar.agent"

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(identifier).plist")
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func install() throws {
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": identifier,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    func uninstall() throws {
        guard isInstalled else { return }
        try fileManager.removeItem(at: plistURL)
    }
}
