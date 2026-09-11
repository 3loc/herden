import SwiftUI

/// App entry point. M0 ships only the buildable skeleton; the Console UI
/// arrives in M1 once the Transport underneath it exists.
@main
struct HerdenApp: App {
    /// APNs delivers device tokens through UIApplicationDelegate callbacks
    /// only, so push bootstrap (#71) needs this adaptor.
    @UIApplicationDelegateAdaptor(PushRegistrationDelegate.self)
    private var pushDelegate

    init() {
        SharedAppStorage.migrateSharedStateIfNeeded()
        Brand.registerFonts()
        try? ImagePreparer.cleanupRemnants()
        try? FilePreparer.cleanupRemnants()
        try? HerdenAudioRecorder.cleanupRemnants()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
                if DemoScreenshotMode.isEnabled {
                    DemoScreenshotRootView()
                } else {
                    productionContent
                }
            #else
                productionContent
            #endif
        }
    }

    private var productionContent: some View {
        ContentView(
            pushRegistration: pushDelegate.registration,
            notificationRouter: pushDelegate.notificationRouter)
    }
}
