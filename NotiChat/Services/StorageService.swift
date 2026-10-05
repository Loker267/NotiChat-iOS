import Foundation
import Combine

public final class StorageService: ObservableObject {
    public static let shared = StorageService()

    @Published public var myIdentity: UserIdentity?
    @Published public var chats: [Chat] = []
    @Published public var messagesByChatId: [String: [ChatMessage]] = [:]

    private let identityKey = "notichat_my_identity"
    private let chatsFileName = "chats.json"
    private let messagesFileName = "messages.json"

    private init() {
        loadIdentity()
        loadChats()
        loadMessages()
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Identity Management
    public func loadIdentity() {
        if let data = UserDefaults.standard.data(forKey: identityKey),
           let identity = try? JSONDecoder().decode(UserIdentity.self, data: data) {
            self.myIdentity = identity
        } else {
            // Generate initial identity
            do {
                let keys = try CryptoUtils.generateRSAKeyPair()
                let newIdentity = UserIdentity(
                    displayName: "iOS_User_\(Int.random(in: 1000...9999))",
                    publicKey: keys.publicKey,
                    privateKey: keys.privateKey
                )
                saveIdentity(newIdentity)
            } catch {
                print("Failed to generate initial RSA identity: \(error)")
            }
        }
    }

    public func saveIdentity(_ identity: UserIdentity) {
        self.myIdentity = identity
        if let data = try? JSONEncoder().encode(identity) {
            UserDefaults.standard.set(data, forKey: identityKey)
        }
    }

    public func updateDisplayName(_ name: String) {
        guard var id = myIdentity else { return }
        id.displayName = name
        saveIdentity(id)
    }

    // MARK: - Chats & Messages Persistence
    public func loadChats() {
        let url = documentsDirectory.appendingPathComponent(chatsFileName)
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Chat].self, data: data) else { return }
        self.chats = list.sorted { $0.timestamp > $1.timestamp }
    }

    public func saveChats() {
        let url = documentsDirectory.appendingPathComponent(chatsFileName)
        if let data = try? JSONEncoder().encode(chats) {
            try? data.write(to: url)
        }
    }

    public func loadMessages() {
        let url = documentsDirectory.appendingPathComponent(messagesFileName)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [ChatMessage]].self, data: data) else { return }
        self.messagesByChatId = dict
    }

    public func saveMessages() {
        let url = documentsDirectory.appendingPathComponent(messagesFileName)
        if let data = try? JSONEncoder().encode(messagesByChatId) {
            try? data.write(to: url)
        }
    }

    // MARK: - CRUD
    public func upsertChat(_ chat: Chat) {
        if let idx = chats.firstIndex(where: { $0.recipientPublicKey == chat.recipientPublicKey }) {
            chats[idx] = chat
        } else {
            chats.insert(chat, at: 0)
        }
        chats.sort { $0.timestamp > $1.timestamp }
        saveChats()
    }

    public func addMessage(_ message: ChatMessage) {
        var list = messagesByChatId[message.chatPublicKeyId] ?? []
        // Avoid duplicate messages
        if !list.contains(where: { $0.id == message.id }) {
            list.append(message)
            list.sort { $0.timestamp < $1.timestamp }
            messagesByChatId[message.chatPublicKeyId] = list
            saveMessages()
        }

        // Update chat's last message
        if let idx = chats.firstIndex(where: { $0.recipientPublicKey == message.chatPublicKeyId }) {
            var chat = chats[idx]
            chat.lastMessage = message.decryptedText
            chat.timestamp = message.timestamp
            chats[idx] = chat
            chats.sort { $0.timestamp > $1.timestamp }
            saveChats()
        }
    }

    public func deleteChat(recipientPublicKey: String) {
        chats.removeAll { $0.recipientPublicKey == recipientPublicKey }
        messagesByChatId.removeValue(forKey: recipientPublicKey)
        saveChats()
        saveMessages()
    }
}
