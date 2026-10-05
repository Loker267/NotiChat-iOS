import SwiftUI

public struct ChatRoomView: View {
    let chat: Chat
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var ntfy = NtfyService.shared
    @State private var inputText = ""
    @State private var isSending = false

    var messages: [ChatMessage] {
        storage.messagesByChatId[chat.recipientPublicKey] ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 10) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 34, height: 34)
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(chat.recipientName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isSending = true

        ntfy.sendMessage(
            recipientName: chat.recipientName,
            recipientPublicKeyStr: chat.recipientPublicKey,
            recipientFcmToken: chat.recipientFcmToken,
            messageText: text
        ) { _ in
            isSending = false
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer() }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                Text(message.decryptedText)
                    .font(.system(size: 16))
                    .foregroundColor(message.isOutgoing ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        message.isOutgoing
                            ? Color.blue
                            : Color(.systemGray5)
                    )
                    .cornerRadius(18)

                Text(formatTimestamp(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !message.isOutgoing { Spacer() }
        }
    }

    private func formatTimestamp(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
