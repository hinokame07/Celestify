//
//  OfflineCrypto.swift
//  Celestify
//
//  Seekable AES-CTR offline audio encryption (`MSE1` + 16-byte IV + ciphertext)
//  backed by a 256-bit Keychain hardware-protected key, plus an `AVAssetResourceLoaderDelegate`
//  allowing `AVPlayer` to stream encrypted offline files in-memory without writing plaintext.
//  Ported from Myspoti (OfflineCrypto.kt, GPL-3.0).
//

import AVFoundation
import CommonCrypto
import Foundation

public enum OfflineCryptoError: Error, LocalizedError, Sendable {
    case invalidKeyLength
    case invalidHeader
    case cryptorFailure(CCCryptorStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKeyLength: return "Offline master key must be 32 bytes (AES-256)."
        case .invalidHeader: return "Encrypted offline file header is missing MSE1 magic."
        case .cryptorFailure(let status): return "CommonCrypto AES-CTR status \(status)."
        }
    }
}

public enum OfflineCrypto {
    public static let magicBytes: [UInt8] = Array("MSE1".utf8)
    public static let ivLength = 16
    public static let headerLength = 4 + ivLength

    public static func isEncryptedFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: 4) else {
            return false
        }
        try? handle.close()
        return [UInt8](head) == magicBytes
    }

    /// Encrypts plaintext audio data into `MSE1` + 16-byte random IV + AES-256-CTR stream.
    public static func encryptData(_ plaintext: Data, masterKey: Data) throws -> Data {
        guard masterKey.count == kCCKeySizeAES256 else {
            throw OfflineCryptoError.invalidKeyLength
        }
        var iv = [UInt8](repeating: 0, count: ivLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, ivLength, &iv)
        let cipher = try aesCTRTransform(input: plaintext, key: masterKey, baseIV: iv, streamByteOffset: 0)
        var out = Data(capacity: headerLength + cipher.count)
        out.append(contentsOf: magicBytes)
        out.append(contentsOf: iv)
        out.append(cipher)
        return out
    }

    /// Decrypts an arbitrary byte slice `[offset ..< offset + length]` of the audio stream using seekable AES-256-CTR.
    public static func decryptSlice(
        fromEncryptedFile fileURL: URL,
        streamOffset: UInt64,
        length: Int,
        masterKey: Data
    ) throws -> Data {
        guard masterKey.count == kCCKeySizeAES256 else {
            throw OfflineCryptoError.invalidKeyLength
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        guard let header = try handle.read(upToCount: headerLength),
              header.count == headerLength,
              Array(header[0..<4]) == magicBytes else {
            throw OfflineCryptoError.invalidHeader
        }
        let iv = Array(header[4..<headerLength])

        try handle.seek(toOffset: UInt64(headerLength) + streamOffset)
        guard let encryptedChunk = try handle.read(upToCount: length), !encryptedChunk.isEmpty else {
            return Data()
        }
        return try aesCTRTransform(input: encryptedChunk, key: masterKey, baseIV: iv, streamByteOffset: streamOffset)
    }

    public static func plaintextLength(ofEncryptedFile fileURL: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let total = (attrs?[.size] as? Int64) ?? 0
        return max(0, total - Int64(headerLength))
    }

    // MARK: - Seekable AES-256-CTR Counter Arithmetic

    public static func aesCTRTransform(
        input: Data,
        key: Data,
        baseIV: [UInt8],
        streamByteOffset: UInt64
    ) throws -> Data {
        let blockIndex = streamByteOffset / 16
        let blockSubOffset = Int(streamByteOffset % 16)
        let counterBlock = incrementCounter128(baseIV, by: blockIndex)

        // Prepend `blockSubOffset` zero bytes so CommonCrypto advances keystream to exact byte offset
        var paddedInput = Data(count: blockSubOffset)
        paddedInput.append(input)
        var paddedOutput = Data(count: paddedInput.count)

        var cryptor: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
            counterBlock.withUnsafeBytes { ivPtr -> CCCryptorStatus in
                CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress,
                    kCCKeySizeAES256,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }
        guard createStatus == kCCSuccess, let validCryptor = cryptor else {
            throw OfflineCryptoError.cryptorFailure(createStatus)
        }
        defer { CCCryptorRelease(validCryptor) }

        var moved: Int = 0
        let outCapacity = paddedOutput.count
        let updateStatus = paddedInput.withUnsafeBytes { inPtr -> CCCryptorStatus in
            paddedOutput.withUnsafeMutableBytes { outPtr -> CCCryptorStatus in
                CCCryptorUpdate(
                    validCryptor,
                    inPtr.baseAddress,
                    paddedInput.count,
                    outPtr.baseAddress,
                    outCapacity,
                    &moved
                )
            }
        }
        guard updateStatus == kCCSuccess else {
            throw OfflineCryptoError.cryptorFailure(updateStatus)
        }
        return paddedOutput.subdata(in: blockSubOffset..<moved)
    }

    private static func incrementCounter128(_ iv: [UInt8], by blocks: UInt64) -> [UInt8] {
        var out = iv
        var carry = blocks
        for idx in stride(from: 15, through: 0, by: -1) where carry > 0 {
            let sum = UInt64(out[idx]) + (carry & 0xFF)
            out[idx] = UInt8(sum & 0xFF)
            carry = (carry >> 8) + (sum >> 8)
        }
        return out
    }
}

// MARK: - AVPlayer Custom Scheme Resource Loader (`celestify-enc://`)

public final class OfflineCryptoAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    public static let customScheme = "celestify-enc"

    private let fileURL: URL
    private let masterKey: Data
    private let contentTypeUTI: String

    public init(fileURL: URL, masterKey: Data, contentTypeUTI: String = "public.mpeg-4-audio") {
        self.fileURL = fileURL
        self.masterKey = masterKey
        self.contentTypeUTI = contentTypeUTI
        super.init()
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let totalLength = OfflineCrypto.plaintextLength(ofEncryptedFile: fileURL)

        if let info = loadingRequest.contentInformationRequest {
            info.contentType = contentTypeUTI
            info.contentLength = totalLength
            info.isByteRangeAccessSupported = true
        }

        if let dataReq = loadingRequest.dataRequest {
            let startOffset = UInt64(max(0, dataReq.currentOffset != 0 ? dataReq.currentOffset : dataReq.requestedOffset))
            let remaining = Int(max(0, totalLength - Int64(startOffset)))
            let requestedLen = dataReq.requestsAllDataToEndOfResource
                ? remaining
                : min(dataReq.requestedLength, remaining)

            do {
                let plainChunk = try OfflineCrypto.decryptSlice(
                    fromEncryptedFile: fileURL,
                    streamOffset: startOffset,
                    length: requestedLen,
                    masterKey: masterKey
                )
                dataReq.respond(with: plainChunk)
                loadingRequest.finishLoading()
            } catch {
                loadingRequest.finishLoading(with: error)
            }
            return true
        }

        loadingRequest.finishLoading()
        return true
    }
}
