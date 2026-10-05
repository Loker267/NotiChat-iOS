import Foundation
import Security
import CommonCrypto
import CryptoKit

public enum CryptoError: Error {
    case keyGenerationFailed
    case invalidKeyFormat
    case encryptionFailed
    case decryptionFailed
    case invalidCiphertextLength
}

public final class CryptoUtils {

    // MARK: - SHA256 Topic derivation matching Android exactly
    public static func getTopicIdFromPublicKey(_ publicKey: String) -> String {
        let cleanKey = publicKey
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let data = cleanKey.data(using: .utf8) else {
            return "notichat_\(cleanKey.hashValue)"
        }
        
        let hash = SHA256.hash(data: data)
        let hexString = hash.map { String(format: "%02x", $0) }.joined()
        return "notichat_" + String(hexString.prefix(24))
    }

    // MARK: - RSA 2048 Key Generation
    public static func generateRSAKeyPair() throws -> (publicKey: String, privateKey: String) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateSecKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicSecKey = SecKeyCopyPublicKey(privateSecKey) else {
            throw CryptoError.keyGenerationFailed
        }
        
        guard let privData = SecKeyCopyExternalRepresentation(privateSecKey, &error) as Data?,
              let pubData = SecKeyCopyExternalRepresentation(publicSecKey, &error) as Data? else {
            throw CryptoError.keyGenerationFailed
        }
        
        // Android expects X.509 format for public key. Wrap PKCS#1 in X.509 header if needed.
        let x509PubData = wrapPKCS1InX509(pubData)
        let pubStr = x509PubData.base64EncodedString()
        let privStr = privData.base64EncodedString()
        
        return (publicKey: pubStr, privateKey: privStr)
    }

    // MARK: - RSA Key Parsing
    public static func secKeyFromPublicKeyString(_ keyStr: String) throws -> SecKey {
        guard var keyData = Data(base64Encoded: keyStr.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")) else {
            throw CryptoError.invalidKeyFormat
        }
        
        // Strip X.509 ASN.1 header if present to get pure PKCS#1 DER for iOS SecKey
        keyData = stripX509HeaderIfPresent(keyData)
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw CryptoError.invalidKeyFormat
        }
        return secKey
    }

    public static func secKeyFromPrivateKeyString(_ keyStr: String) throws -> SecKey {
        guard let keyData = Data(base64Encoded: keyStr.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")) else {
            throw CryptoError.invalidKeyFormat
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw CryptoError.invalidKeyFormat
        }
        return secKey
    }

    // MARK: - RSA Encryption / Decryption of Session Key (PKCS1Padding)
    public static func encryptKeyRSA(aesKey: Data, recipientPublicKeyStr: String) throws -> String {
        let secKey = try secKeyFromPublicKeyString(recipientPublicKeyStr)
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, aesKey as CFData, &error) as Data? else {
            throw CryptoError.encryptionFailed
        }
        return encryptedData.base64EncodedString()
    }

    public static func decryptKeyRSA(encryptedAesKeyBase64: String, myPrivateKeyStr: String) throws -> Data {
        guard let encryptedData = Data(base64Encoded: encryptedAesKeyBase64) else {
            throw CryptoError.invalidKeyFormat
        }
        let secKey = try secKeyFromPrivateKeyString(myPrivateKeyStr)
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(secKey, .rsaEncryptionPKCS1, encryptedData as CFData, &error) as Data? else {
            throw CryptoError.decryptionFailed
        }
        return decryptedData
    }

    // MARK: - AES 256 CBC (IV 16 bytes + Ciphertext)
    public static func generateAESKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }

    public static func encryptAES(plainText: String, aesKey: Data) throws -> String {
        guard let textData = plainText.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        
        var iv = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &iv)
        
        let bufferSize = textData.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var bytesEncrypted: size_t = 0
        
        let status = aesKey.withUnsafeBytes { keyBytes in
            textData.withUnsafeBytes { dataBytes in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress,
                    kCCKeySizeAES256,
                    iv,
                    dataBytes.baseAddress,
                    textData.count,
                    &buffer,
                    bufferSize,
                    &bytesEncrypted
                )
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.encryptionFailed
        }
        
        var combined = Data(iv)
        combined.append(Data(buffer.prefix(bytesEncrypted)))
        return combined.base64EncodedString()
    }

    public static func decryptAES(encryptedBase64: String, aesKey: Data) throws -> String {
        guard let combined = Data(base64Encoded: encryptedBase64), combined.count >= 16 else {
            throw CryptoError.invalidCiphertextLength
        }
        
        let iv = combined.subdata(in: 0..<16)
        let ciphertext = combined.subdata(in: 16..<combined.count)
        
        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var bytesDecrypted: size_t = 0
        
        let status = aesKey.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                ciphertext.withUnsafeBytes { cipherBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        kCCKeySizeAES256,
                        ivBytes.baseAddress,
                        cipherBytes.baseAddress,
                        ciphertext.count,
                        &buffer,
                        bufferSize,
                        &bytesDecrypted
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.decryptionFailed
        }
        
        let decryptedData = Data(buffer.prefix(bytesDecrypted))
        guard let string = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        return string
    }

    // MARK: - ASN.1 Helpers
    private static let rsaX509Header: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86,
        0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
        0x82, 0x01, 0x0f, 0x00
    ]

    private static func wrapPKCS1InX509(_ pkcs1: Data) -> Data {
        if pkcs1.count == 270 {
            var full = Data(rsaX509Header)
            full.append(pkcs1)
            return full
        }
        return pkcs1
    }

    private static func stripX509HeaderIfPresent(_ data: Data) -> Data {
        // If data is standard 294-byte X.509 SubjectPublicKeyInfo, strip first 24 bytes
        if data.count == 294 && data.starts(with: [0x30, 0x82]) {
            return data.subdata(in: 24..<data.count)
        }
        return data
    }
}
