import Foundation

public struct UserIdentity: Codable, Identifiable {
    public var id: String { publicKey }
    public var displayName: String
    public var publicKey: String
    public var privateKey: String
    public var fcmToken: String

    public init(displayName: String, publicKey: String, privateKey: String, fcmToken: String = "") {
        self.displayName = displayName
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.fcmToken = fcmToken
    }
}

public struct Chat: Codable, Identifiable, Hashable {
    public var id: String { recipientPublicKey }
    public var recipientPublicKey: String
    public var recipientName: String
    public var recipientFcmToken: String
    public var lastMessage: String
    public var timestamp: Int64

    public init(recipientPublicKey: String, recipientName: String, recipientFcmToken: String = "", lastMessage: String = "", timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.recipientPublicKey = recipientPublicKey
        self.recipientName = recipientName
        self.recipientFcmToken = recipientFcmToken
        self.lastMessage = lastMessage
        self.timestamp = timestamp
    }
}

public struct ChatMessage: Codable, Identifiable, Hashable {
    public var id: String
    public var chatPublicKeyId: String
    public var senderPublicKey: String
    public var recipientPublicKey: String
    public var encryptedText: String
    public var decryptedText: String
    public var encryptedSessionKey: String
    public var isOutgoing: Bool
    public var timestamp: Int64
    public var isDecryptedSuccessfully: Bool

    public init(
        id: String = UUID().uuidString,
        chatPublicKeyId: String,
        senderPublicKey: String,
        recipientPublicKey: String,
        encryptedText: String,
        decryptedText: String,
        encryptedSessionKey: String,
        isOutgoing: Bool,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isDecryptedSuccessfully: Bool = true
    ) {
        self.id = id
        self.chatPublicKeyId = chatPublicKeyId
        self.senderPublicKey = senderPublicKey
        self.recipientPublicKey = recipientPublicKey
        self.encryptedText = encryptedText
        self.decryptedText = decryptedText
        self.encryptedSessionKey = encryptedSessionKey
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.isDecryptedSuccessfully = isDecryptedSuccessfully
    }
}

public struct NtfyWirePayload: Codable {
    public var sender_name: String
    public var sender_public_key: String
    public var encrypted_text: String
    public var encrypted_session_key: String
    public var sender_fcm_token: String
    public var timestamp: String

    public init(sender_name: String, sender_public_key: String, encrypted_text: String, encrypted_session_key: String, sender_fcm_token: String = "", timestamp: String = String(Int64(Date().timeIntervalSince1970 * 1000))) {
        self.sender_name = sender_name
        self.sender_public_key = sender_public_key
        self.encrypted_text = encrypted_text
        self.encrypted_session_key = encrypted_session_key
        self.sender_fcm_token = sender_fcm_token
        self.timestamp = timestamp
    }
}
