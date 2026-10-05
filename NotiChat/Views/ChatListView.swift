import SwiftUI

public struct ChatListView: View {
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var ntfy = NtfyService.shared
    @State private var showingProfile = false
    @State private var showingNewChat = false
    @State private var searchText = ""

    var filteredChats: [Chat] {
        if searchText.isEmpty {
            return storage.chats
        } else {
            return storage.chats.filter {
                $0.recipientName.localizedCaseInsensitiveContains(searchText) ||
                $0.lastMessage.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    public var body: some View {
        NavigationView {
            List {
                if storage.chats.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No chats yet")
                            .font(.headline)
                        Text("Tap + to add a friend using their Public Key from Android.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredChats) { chat in
                        NavigationLink(destination: ChatRoomView(chat: chat)) {
                            ChatRow(chat: chat)
                        }
                    }
                    .onDelete(perform: deleteChats)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .searchable(text: $searchText, prompt: "Search chats")
            .navigationTitle("NotiChat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingProfile = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 20))
                            Circle()
                                .fill(ntfy.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewChat = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18))
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView()
            }
        }
    }

    private func deleteChats(at offsets: IndexSet) {
        for index in offsets {
            let chat = filteredChats[index]
            storage.deleteChat(recipientPublicKey: chat.recipientPublicKey)
        }
    }
}

struct ChatRow: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 14) {
            // Avatar with initials
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)

                Text(chat.recipientName.prefix(1).uppercased())
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.recipientName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(formatTimestamp(chat.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(chat.lastMessage.isEmpty ? "No messages" : chat.lastMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTimestamp(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts / 1000))
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "dd.MM"
        }
        return formatter.string(from: date)
    }
}
