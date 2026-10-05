import SwiftUI

@main
struct NotiChatApp: App {
    @StateObject private var storage = StorageService.shared
    @StateObject private var ntfy = NtfyService.shared

    var body: some Scene {
        WindowGroup {
            ChatListView()
                .onAppear {
                    ntfy.startListening()
                }
        }
    }
}
