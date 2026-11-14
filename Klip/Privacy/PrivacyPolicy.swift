import Observation

@MainActor
@Observable
final class PrivacyPolicy {
    var isPaused = false
    // Best-effort source attribution; never a guarantee that a copy is nonsensitive.
    var excludedApplicationIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "com.apple.keychainaccess"
    ]

    func allowsCapture(from applicationID: String?) -> Bool {
        !isPaused && !excludedApplicationIDs.contains(applicationID ?? "")
    }
}
