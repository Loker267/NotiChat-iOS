import SwiftUI
import CoreImage.CIFilterBuiltins

public struct ChatListView: View {
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var ntfy = NtfyService.shared
    @State private var showingProfile = false
    @State private var showingNewChat = false
    @State private var searchText = ""
    @State private var isIdentityExpanded = false
    @State private var copiedKey = false

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
            ScrollView {
                VStack(spacing: 14) {
                    // Top Card: "Ваш защищенный идентификатор E2EE" matching Android 1:1
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("🔒 ВАШ ИДЕНТИФИКАТОР E2EE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)

                                Text(storage.myIdentity?.displayName ?? "Пользователь...")
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }

                            Spacer()

                            Button(action: {
                                withAnimation(.spring()) {
                                    isIdentityExpanded.toggle()
                                }
                            }) {
                                Text(isIdentityExpanded ? "Свернуть" : "Ключ и QR")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(12)
                            }
                        }

                        if isIdentityExpanded {
                            Divider()

                            if let key = storage.myIdentity?.publicKey {
                                Text("Ваш публичный RSA-ключ:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text(key)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(3)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)

                                HStack {
                                    Button(action: {
                                        UIPasteboard.general.string = key
                                        copiedKey = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedKey = false }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: copiedKey ? "checkmark" : "doc.on.doc")
                                            Text(copiedKey ? "Скопировано!" : "Скопировать ключ")
                                        }
                                        .font(.footnote)
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(ntfy.isConnected ? Color.green : Color.red)
                                            .frame(width: 8, height: 8)
                                        Text(ntfy.isConnected ? "В сети (ntfy)" : "Подключение...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                if let qr = generateQRCode(from: key) {
                                    HStack {
                                        Spacer()
                                        Image(uiImage: qr)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                            .padding(6)
                                            .background(Color.white)
                                            .cornerRadius(10)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
                    .padding(.horizontal, 16)

                    // Chats Section Header
                    HStack {
                        Text("ДИАЛОГИ")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(storage.chats.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)

                    // Chats List Items
                    if storage.chats.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 42))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("Нет активных чатов")
                                .font(.headline)
                            Text("Нажмите «+ Новый чат» внизу, чтобы добавить контакт по публичному ключу.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredChats) { chat in
                                NavigationLink(destination: ChatRoomView(chat: chat)) {
                                    ChatRow(chat: chat)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        storage.deleteChat(recipientPublicKey: chat.recipientPublicKey)
                                    } label: {
                                        Label("Удалить чат", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Поиск диалогов...")
            .navigationTitle("NotiChat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingProfile = true }) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewChat = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Чат")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
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

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
