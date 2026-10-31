import Foundation
import ServiceManagement

/// Launch at login is registered against the app's location. When Quill moves (the build folder
/// to /Applications, 10/31), re-register so the login item opens the copy that's actually here.
enum LoginItem {
    private static let pathKey = "loginItemPath"

    static func followMove() {
        let here = Bundle.main.bundlePath
        let defaults = UserDefaults.standard
        guard SMAppService.mainApp.status == .enabled, defaults.string(forKey: pathKey) != here else {
            if SMAppService.mainApp.status == .enabled { defaults.set(here, forKey: pathKey) }
            return
        }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            defaults.set(here, forKey: pathKey)
            Log.write("launch at login re-registered for \(here)")
        } catch {
            Log.write("launch at login re-register failed: \(error)")
        }
    }
}
