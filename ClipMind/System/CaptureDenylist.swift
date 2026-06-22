import Foundation

enum CaptureDenylist {
    private static let deniedBundleIDs: Set<String> = [
        // Password managers
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "2BUA8C4S2C.com.1password",
        "com.bitwarden.desktop",
        // Keychain
        "com.apple.keychainaccess",
        // Banking (representative bundle IDs)
        "com.chase",
        "com.chase.sig.android",
        "com.bankofamerica.BofA",
        "com.wf.wellsfargomobile",
        "com.citi.citimobile",
        "com.usaa.mobile.android.usaa",
        "com.capitalone.mobile",
    ]

    private static let neverDeniedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
    ]

    static func shouldIgnore(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else {
            return false
        }

        if neverDeniedBundleIDs.contains(bundleID) {
            return false
        }

        return deniedBundleIDs.contains(bundleID)
    }
}
