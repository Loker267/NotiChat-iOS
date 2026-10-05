import SwiftUI
import CoreImage.CIFilterBuiltins

public struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageService.shared
    @ObservedObject var ntfy = NtfyService.shared
    @State private var name: String = ""
    @State private var copied = false

    public var body: some View {
        NavigationView {
            Form {
                Section(header: Text("My Identity")) {
                    HStack {
                        Text("Display Name")
                        Spacer()
                        TextField("Name", text: $name, onCommit: saveName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.blue)
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ntfy.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(ntfy.isConnected ? "Online (Connected)" : "Connecting...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("My Public Key (RSA 2048)")) {
                    if let key = storage.myIdentity?.publicKey {
                        Text(key)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(4)
                            .foregroundColor(.secondary)

                        Button(action: {
                            UIPasteboard.general.string = key
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        }) {
                            HStack {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy Public Key")
                            }
                            .foregroundColor(.blue)
                        }

                        // QR Code
                        VStack(alignment: .center) {
                            if let qr = generateQRCode(from: key) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .padding(.vertical, 8)
                            }
                            Text("Scan this QR code from Android to start chatting")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Profile & Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveName()
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = storage.myIdentity?.displayName ?? ""
            }
        }
    }

    private func saveName() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty {
            storage.updateDisplayName(clean)
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
