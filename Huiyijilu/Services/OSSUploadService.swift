//
//  OSSUploadService.swift
//  Huiyijilu
//
//  阿里云OSS上传服务（纯Swift实现，async/await）
//  上传音频/文件到公开 OSS bucket，返回 HTTPS URL。
//

import Foundation
import CommonCrypto

/// 阿里云OSS上传服务 — 用于上传音频文件并返回公开可访问的 HTTPS URL
class OSSUploadService {

    static let shared = OSSUploadService()

    // MARK: - OSS 配置（从 UserDefaults 读取，在「设置」中配置）
    private var accessKeyId:     String { UserDefaults.standard.string(forKey: "oss_access_key_id")     ?? "" }
    private var accessKeySecret: String { UserDefaults.standard.string(forKey: "oss_access_key_secret") ?? "" }
    private var endpoint:        String { UserDefaults.standard.string(forKey: "oss_endpoint")          ?? "oss-cn-shanghai.aliyuncs.com" }
    private var bucketName:      String { UserDefaults.standard.string(forKey: "oss_bucket_name")       ?? "" }
    private let uploadPath      = "meetings/audio/"
    private var publicBaseURL: String { "https://\(bucketName).\(endpoint)/" }

    private init() {}

    private func log(_ msg: String) { print("[OSS] \(msg)") }

    // MARK: - Upload Audio (async)

    /// Upload a local audio file to OSS and return a public HTTPS URL.
    func uploadAudio(localURL: URL) async throws -> String {
        let fileData = try Data(contentsOf: localURL)
        let fileName = localURL.lastPathComponent
        let ext = localURL.pathExtension.lowercased()

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uuid = UUID().uuidString.prefix(8)
        let objectKey = "\(uploadPath)\(timestamp)_\(uuid).\(ext)"

        let contentType: String = {
            switch ext {
            case "m4a":  return "audio/mp4"
            case "mp3":  return "audio/mpeg"
            case "wav":  return "audio/wav"
            case "aac":  return "audio/aac"
            case "mp4":  return "video/mp4"
            default:     return "application/octet-stream"
            }
        }()

        log("📤 Uploading \(fileName) (\(fileData.count) bytes) → \(objectKey)")

        let urlStr = "https://\(bucketName).\(endpoint)/\(objectKey)"
        guard let url = URL(string: urlStr) else {
            throw OSSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = fileData
        request.timeoutInterval = 180

        let date = httpDateString()
        let contentMD5 = fileData.ossmd5Base64()

        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(date, forHTTPHeaderField: "Date")
        request.setValue(contentMD5, forHTTPHeaderField: "Content-MD5")
        request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")

        let signature = calculateSignature(
            httpMethod: "PUT",
            contentMD5: contentMD5,
            contentType: contentType,
            date: date,
            resource: "/\(bucketName)/\(objectKey)"
        )
        request.setValue("OSS \(accessKeyId):\(signature)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OSSError.invalidResponse
        }

        guard (200...201).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            log("❌ HTTP \(http.statusCode): \(body)")
            throw OSSError.uploadFailed(http.statusCode, body)
        }

        let publicURL = "\(publicBaseURL)\(objectKey)"
        log("✅ Uploaded → \(publicURL)")
        return publicURL
    }

    // MARK: - Helpers

    private func httpDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(abbreviation: "GMT")
        return fmt.string(from: Date())
    }

    private func calculateSignature(httpMethod: String, contentMD5: String, contentType: String, date: String, resource: String) -> String {
        let stringToSign = "\(httpMethod)\n\(contentMD5)\n\(contentType)\n\(date)\n\(resource)"
        return hmacSHA1(string: stringToSign, key: accessKeySecret)
    }

    private func hmacSHA1(string: String, key: String) -> String {
        guard let data = string.data(using: .utf8),
              let keyData = key.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyBytes.baseAddress, keyData.count,
                       dataBytes.baseAddress, data.count,
                       &digest)
            }
        }
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Data MD5

private extension Data {
    func ossmd5Base64() -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(count), &digest)
        }
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Errors

enum OSSError: LocalizedError {
    case invalidURL
    case invalidResponse
    case uploadFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:                 return "OSS URL 构建失败"
        case .invalidResponse:            return "OSS 无效响应"
        case .uploadFailed(let c, let m): return "OSS 上传失败 HTTP \(c): \(m)"
        }
    }
}
