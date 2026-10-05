import SwiftUI

public struct NewChatView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageService.shared
    @State private var recipientName = ""
    @State private var recipientPublicKey = ""
    @State private var errorMessage = ""
    @State private var showQRScanner = false

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

                        HStack(spacing: 12) {
                            Button(action: pasteFromClipboard) {
                                HStack {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Вставить из буфера")
                                }
                                .font(.footnote)
                            }

                            Spacer()

                            Button(action: { showQRScanner = true }) {
                                HStack {
                                    Image(systemName: "qrcode.viewfinder")
                                    Text("Сканировать QR-код")
                                }
                                .font(.footnote)
                                .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.top, 4)
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
            .sheet(isPresented: $showQRScanner) {
                NavigationView {
                    QRScannerView(
                        onScan: { scannedText in
                            handleScannedCode(scannedText)
                            showQRScanner = false
                        },
                        onDismiss: {
                            showQRScanner = false
                        }
                    )
                    .navigationTitle("Сканировать QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Закрыть") { showQRScanner = false }
                        }
                    }
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check if QR code is formatted as JSON or pure key or key with prefix
        recipientPublicKey = trimmed
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
