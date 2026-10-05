import SwiftUI

public struct NewChatView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageService.shared
    @State private var recipientName = ""
    @State private var recipientPublicKey = ""
    @State private var errorMessage = ""

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Recipient Info")) {
                    TextField("Name (e.g. Android Friend)", text: $recipientName)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Public Key (RSA 2048)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $recipientPublicKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )

                        Button(action: pasteFromClipboard) {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                Text("Paste from Clipboard")
                            }
                            .font(.footnote)
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") { createChat() }
                        .disabled(recipientName.trimmingCharacters(in: .whitespaces).isEmpty || recipientPublicKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func pasteFromClipboard() {
        if let clip = UIPasteboard.general.string {
            recipientPublicKey = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func createChat() {
        let name = recipientName.trimmingCharacters(in: .whitespaces)
        let key = recipientPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !key.isEmpty else { return }

        // Validate public key can be parsed
        do {
            _ = try CryptoUtils.secKeyFromPublicKeyString(key)
        } catch {
            errorMessage = "Invalid RSA Public Key. Please ensure you copied the complete key."
            return
        }

        let newChat = Chat(
            recipientPublicKey: key,
            recipientName: name,
            lastMessage: "Chat created",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        storage.upsertChat(newChat)
        dismiss()
    }
}
