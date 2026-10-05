import Foundation
import UserNotifications
import AudioToolbox

public final class NtfyService: NSObject, ObservableObject, URLSessionDataDelegate {
    public static let shared = NtfyService()

    @Published public var isConnected = false
    private var streamSession: URLSession?
    private var streamTask: URLSessionDataTask?
    private var reconnectTimer: Timer?
    private var currentTopic: String?

    private override init() {
        super.init()
        requestNotificationPermissions()
    }

    // MARK: - Notification Setup
    public func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            }
        }
    }

    // MARK: - Start Listening
    public func startListening() {
        guard let identity = StorageService.shared.myIdentity else { return }
        let myTopic = CryptoUtils.getTopicIdFromPublicKey(identity.publicKey)
        self.currentTopic = myTopic

        streamTask?.cancel()
        streamSession?.invalidateAndCancel()

        guard let url = URL(string: "https://ntfy.sh/\(myTopic)/json") else { return }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        
        streamSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        streamTask = streamSession?.dataTask(with: url)
        streamTask?.resume()
        
        isConnected = true
        print("Connected to ntfy topic: \(myTopic)")
    }

    public func stopListening() {
        streamTask?.cancel()
        streamSession?.invalidateAndCancel()
        isConnected = false
    }

    // MARK: - Sending Messages
    public func sendMessage(
        recipientName: String,
        recipientPublicKeyStr: String,
        recipientFcmToken: String = "",
        messageText: String,
        completion: @escaping (Result<ChatMessage, Error>) -> Void
    ) {
        guard let myIdentity = StorageService.shared.myIdentity else {
            completion(.failure(CryptoError.keyGenerationFailed))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 1. Generate AES 256 Key
                let aesKey = CryptoUtils.generateAESKey()
                
                // 2. Encrypt text with AES
                let encryptedText = try CryptoUtils.encryptAES(plainText: messageText, aesKey: aesKey)
                
                // 3. Encrypt AES Key with recipient RSA Public Key
                let encryptedSessionKey = try CryptoUtils.encryptKeyRSA(aesKey: aesKey, recipientPublicKeyStr: recipientPublicKeyStr)

                let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

                // 4. Save local chat & outgoing message
                let outgoingMsg = ChatMessage(
                    chatPublicKeyId: recipientPublicKeyStr,
                    senderPublicKey: myIdentity.publicKey,
                    recipientPublicKey: recipientPublicKeyStr,
                    encryptedText: encryptedText,
                    decryptedText: messageText,
                    encryptedSessionKey: encryptedSessionKey,
                    isOutgoing: true,
                    timestamp: timestamp,
                    isDecryptedSuccessfully: true
                )

                let chat = Chat(
                    recipientPublicKey: recipientPublicKeyStr,
                    recipientName: recipientName,
                    recipientFcmToken: recipientFcmToken,
                    lastMessage: messageText,
                    timestamp: timestamp
                )

                DispatchQueue.main.async {
                    StorageService.shared.upsertChat(chat)
                    StorageService.shared.addMessage(outgoingMsg)
                }

                // 5. Post to ntfy.sh
                let recipientTopic = CryptoUtils.getTopicIdFromPublicKey(recipientPublicKeyStr)
                guard let ntfyUrl = URL(string: "https://ntfy.sh/\(recipientTopic)") else {
                    DispatchQueue.main.async { completion(.success(outgoingMsg)) }
                    return
                }

                let wirePayload = NtfyWirePayload(
                    sender_name: myIdentity.displayName,
                    sender_public_key: myIdentity.publicKey,
                    encrypted_text: encryptedText,
                    encrypted_session_key: encryptedSessionKey,
                    sender_fcm_token: myIdentity.fcmToken,
                    timestamp: String(timestamp)
                )

                var request = URLRequest(url: ntfyUrl)
                request.httpMethod = "POST"
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(wirePayload)

                let postTask = URLSession.shared.dataTask(with: request) { _, _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("Error sending message to ntfy: \(error)")
                        } else {
                            print("Message dispatched successfully over ntfy.")
                        }
                        completion(.success(outgoingMsg))
                    }
                }
                postTask.resume()

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Handle Incoming Streamed Data
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        
        let lines = text.components(separatedBy: "\n")
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            handleSingleMessageJson(line)
        }
    }

    private func handleSingleMessageJson(_ jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let event = json["event"] as? String, event == "message",
              let rawMessage = json["message"] as? String else {
            return
        }

        // The message field inside ntfy event contains our NtfyWirePayload JSON string
        guard let payloadData = rawMessage.data(using: .utf8),
              let wire = try? JSONDecoder().decode(NtfyWirePayload.self, from: payloadData) else {
            return
        }

        guard let myIdentity = StorageService.shared.myIdentity else { return }
        // Ignore our own echoed messages
        if wire.sender_public_key == myIdentity.publicKey { return }

        DispatchQueue.global(qos: .userInitiated).async {
            var decryptedText = ""
            var success = false

            do {
                // Decrypt AES Session Key
                let aesKey = try CryptoUtils.decryptKeyRSA(
                    encryptedAesKeyBase64: wire.encrypted_session_key,
                    myPrivateKeyStr: myIdentity.privateKey
                )
                // Decrypt Text
                decryptedText = try CryptoUtils.decryptAES(
                    encryptedBase64: wire.encrypted_text,
                    aesKey: aesKey
                )
                success = true
            } catch {
                print("Decryption failed: \(error)")
                decryptedText = "🔒 [Error: Could not decrypt message]"
                success = false
            }

            let timestamp = Int64(wire.timestamp) ?? Int64(Date().timeIntervalSince1970 * 1000)

            let incomingMsg = ChatMessage(
                chatPublicKeyId: wire.sender_public_key,
                senderPublicKey: wire.sender_public_key,
                recipientPublicKey: myIdentity.publicKey,
                encryptedText: wire.encrypted_text,
                decryptedText: decryptedText,
                encryptedSessionKey: wire.encrypted_session_key,
                isOutgoing: false,
                timestamp: timestamp,
                isDecryptedSuccessfully: success
            )

            let chat = Chat(
                recipientPublicKey: wire.sender_public_key,
                recipientName: wire.sender_name.isEmpty ? "Unknown" : wire.sender_name,
                recipientFcmToken: wire.sender_fcm_token,
                lastMessage: decryptedText,
                timestamp: timestamp
            )

            DispatchQueue.main.async {
                StorageService.shared.upsertChat(chat)
                StorageService.shared.addMessage(incomingMsg)
                
                // Play notification sound & haptic
                AudioServicesPlaySystemSound(1007)
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

                // Local Notification Banner
                self.triggerLocalNotification(title: chat.recipientName, body: decryptedText)
            }
        }
    }

    private func triggerLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("ntfy stream disconnected: \(String(describing: error)). Reconnecting in 3s...")
        isConnected = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.startListening()
        }
    }
}
