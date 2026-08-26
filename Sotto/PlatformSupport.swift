import Foundation

/// Single source of truth for the macOS version Sotto supports. The docs, the
/// `MACOSX_DEPLOYMENT_TARGET` build setting, and the launch gate are all
/// checked against this one value.
enum PlatformSupport {
    static let minimumMacOS = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)

    static var minimumMacOSDisplayString: String {
        "\(minimumMacOS.majorVersion).\(minimumMacOS.minorVersion)"
    }

    enum LaunchOutcome: Equatable {
        case opensMenuBarItem
        case unsupportedMacOSVersion
    }

    static var unsupportedVersionMessage: String {
        "Sotto needs macOS \(minimumMacOSDisplayString) or later. This Mac is running an older version."
    }

    static func launchOutcome(
        hostVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> LaunchOutcome {
        let host = (hostVersion.majorVersion, hostVersion.minorVersion, hostVersion.patchVersion)
        let minimum = (minimumMacOS.majorVersion, minimumMacOS.minorVersion, minimumMacOS.patchVersion)
        return host >= minimum ? .opensMenuBarItem : .unsupportedMacOSVersion
    }
}
