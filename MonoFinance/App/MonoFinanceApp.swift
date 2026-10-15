import SwiftUI
import UIKit

@main
struct MonoFinanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.settings)
                .environment(environment.store)
                .environment(environment.router)
                .environment(environment.toasts)
                .environment(environment.lock)
                .onOpenURL { url in
                    if let command = AppCommand(url: url) { environment.handle(command: command) }
                }
        }
    }
}

/// Быстрые действия с иконки приложения (3D Touch / долгое нажатие).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem, let command = AppCommand(shortcutType: item.type) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                AppEnvironment.shared.handle(command: command)
            }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let command = AppCommand(shortcutType: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        Task { @MainActor in
            AppEnvironment.shared.handle(command: command)
            completionHandler(true)
        }
    }
}
