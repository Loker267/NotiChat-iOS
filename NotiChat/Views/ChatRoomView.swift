import SwiftUI
import PhotosUI

public struct ChatRoomView: View {
    let chat: Chat
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var ntfy = NtfyService.shared
    @State private var inputText = ""
    @State private var isSending = false

    // Media
    @StateObject private var audioRecorder = AudioRecorderManager()
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isSelectingPhoto = false

    // Inspector
    @State private var showingInspector = false
    @State private var selectedMessageForInspection: ChatMessage?

    var messages: [ChatMessage] {
        storage.messagesByChatId[chat.recipientPublicKey] ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            // E2EE Status Sub-header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("Включено сквозное E2EE шифрование (RSA-2048 + AES)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6).opacity(0.6))

            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg) {
                                selectedMessageForInspection = msg
                                showingInspector = true
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input Bar
            HStack(spacing: 10) {
                // Photo Picker button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
                }
                .onChange(of: selectedPhotoItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let base64 = MediaUtils.compressImageToBase64(image) {
                            sendPayload("[IMAGE_E2EE:\(base64)]")
                        }
                    }
                }

                // Text field
                TextField("Сообщение...", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)

                // Send or Voice Record Button
                if inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Mic button for Voice Note
                    Button(action: toggleVoiceRecording) {
                        Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .resizable()
                            .frame(width: 34, height: 34)
                            .foregroundColor(audioRecorder.isRecording ? .red : .blue)
                    }
                } else {
                    // Send text message button
                    Button(action: sendTextMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 34, height: 34)
                            .foregroundColor(.blue)
                    }
                    .disabled(isSending)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(chat.recipientName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if let last = messages.last {
                        selectedMessageForInspection = last
                        showingInspector = true
                    }
                }) {
                    Image(systemName: "lock.shield")
                }
            }
        }
        .sheet(isPresented: $showingInspector) {
            if let msg = selectedMessageForInspection {
                PayloadInspectorSheet(message: msg)
            }
        }
    }

    private func sendTextMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        sendPayload(text)
    }

    private func sendPayload(_ payloadText: String) {
        isSending = true
        ntfy.sendMessage(
            recipientName: chat.recipientName,
            recipientPublicKeyStr: chat.recipientPublicKey,
            recipientFcmToken: chat.recipientFcmToken,
            messageText: payloadText
        ) { _ in
            isSending = false
        }
    }

    private func toggleVoiceRecording() {
        if audioRecorder.isRecording {
            if let base64Audio = audioRecorder.stopRecording() {
                sendPayload("[AUDIO_E2EE:\(base64Audio)]")
            }
        } else {
            _ = audioRecorder.startRecording()
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    let onLongPress: () -> Void

    var isImage: Bool {
        message.decryptedText.hasPrefix("[IMAGE_E2EE:") && message.decryptedText.hasSuffix("]")
    }

    var isAudio: Bool {
        message.decryptedText.hasPrefix("[AUDIO_E2EE:") && message.decryptedText.hasSuffix("]")
    }

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer() }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                Group {
                    if isImage {
                        Base64ImageDisplay(payload: message.decryptedText)
                    } else if isAudio {
                        Base64AudioPlayerDisplay(payload: message.decryptedText, isOutgoing: message.isOutgoing)
                    } else {
                        Text(message.decryptedText)
                            .font(.system(size: 16))
                            .foregroundColor(message.isOutgoing ? .white : .primary)
                    }
                }
                .padding(.horizontal, isImage ? 4 : 14)
                .padding(.vertical, isImage ? 4 : 9)
                .background(
                    message.isOutgoing
                        ? (isImage ? Color.clear : Color.blue)
                        : (isImage ? Color.clear : Color(.systemGray5))
                )
                .cornerRadius(18)
                .onLongPressGesture {
                    onLongPress()
                }

                HStack(spacing: 4) {
                    Text(formatTimestamp(message.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if message.isOutgoing {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
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

// MARK: - In-bubble Image Display
struct Base64ImageDisplay: View {
    let payload: String

    var uiImage: UIImage? {
        let clean = payload.replacingOccurrences(of: "[IMAGE_E2EE:", with: "").replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: clean) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        if let img = uiImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 240, maxHeight: 240)
                .cornerRadius(14)
                .clipped()
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                Text("Ошибка загрузки фото")
            }
            .font(.footnote)
            .padding(10)
        }
    }
}

// MARK: - In-bubble Voice Note Display
struct Base64AudioPlayerDisplay: View {
    let payload: String
    let isOutgoing: Bool
    @StateObject private var player = AudioPlayerManager()

    var cleanBase64: String {
        payload.replacingOccurrences(of: "[AUDIO_E2EE:", with: "").replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                if player.isPlaying {
                    player.stopPlaying()
                } else {
                    player.playAudioFromBase64(cleanBase64) {}
                }
            }) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isOutgoing ? .white : .blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.isPlaying ? "Воспроизведение..." : "Голосовое сообщение")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(isOutgoing ? .white : .primary)
                Text("AAC 16kHz • E2EE")
                    .font(.caption2)
                    .foregroundColor(isOutgoing ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Payload Inspector Sheet
struct PayloadInspectorSheet: View {
    let message: ChatMessage
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("E2EE Детали сообщения")) {
                    HStack {
                        Text("Направление")
                        Spacer()
                        Text(message.isOutgoing ? "Исходящее" : "Входящее")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Статус шифрования")
                        Spacer()
                        Text(message.isDecryptedSuccessfully ? "Успешно расшифровано" : "Ошибка")
                            .foregroundColor(message.isDecryptedSuccessfully ? .green : .red)
                    }
                }

                Section(header: Text("Зашифрованный текст (AES-256)")) {
                    Text(message.encryptedText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Зашифрованный ключ сессии (RSA-2048)")) {
                    Text(message.encryptedSessionKey)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Расшифрованный текст")) {
                    Text(message.decryptedText)
                        .font(.body)
                }
            }
            .navigationTitle("Инспектор пакета")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
