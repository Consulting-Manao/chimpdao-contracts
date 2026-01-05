//
//  IPFSService.swift
//  Chimp
//
//  Service for downloading NFT metadata from IPFS
//

import Foundation
import OSLog

/// NFT metadata structure following SEP-50 standard
struct NFTMetadata: Codable {
    let name: String?
    let description: String?
    let image: String?
    let attributes: [NFTAttribute]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case image
        case attributes
    }
}

/// NFT attribute structure
struct NFTAttribute: Codable {
    let trait_type: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case trait_type = "trait_type"
        case value
    }
}

final class IPFSService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }

    /// Download NFT metadata from IPFS URL
    /// - Parameter ipfsUrl: IPFS URL string
    /// - Returns: NFT metadata
    /// - Throws: AppError if download or parsing fails
    func downloadNFTMetadata(from ipfsUrl: String) async throws -> NFTMetadata {
        Logger.logDebug("Downloading NFT metadata from: \(ipfsUrl)", category: .network)

        guard let url = URL(string: ipfsUrl) else {
            throw AppError.ipfs(.invalidHash)
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            Logger.logDebug("HTTP status: \(httpResponse.statusCode)", category: .network)
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AppError.ipfs(.downloadFailed("HTTP \(httpResponse.statusCode)"))
            }
        }

        // Debug: Check if response looks like HTML (error page)
        if let responseString = String(data: data, encoding: .utf8) {
            if responseString.hasPrefix("<!DOCTYPE") || responseString.hasPrefix("<html") || responseString.contains("<html") {
                Logger.logError("Received HTML instead of JSON. This might be an IPFS gateway error page.", category: .network)
                Logger.logDebug("Response preview: \(responseString.prefix(200))...", category: .network)
                throw AppError.ipfs(.parseFailed("IPFS gateway returned HTML error page instead of JSON"))
            }
        }

        // Parse JSON
        let decoder = JSONDecoder()
        do {
            let metadata = try decoder.decode(NFTMetadata.self, from: data)
            Logger.logDebug("Successfully parsed NFT metadata", category: .network)
            Logger.logDebug("Name: \(metadata.name ?? "N/A")", category: .network)
            Logger.logDebug("Description: \(metadata.description ?? "N/A")", category: .network)
            Logger.logDebug("Image: \(metadata.image ?? "N/A")", category: .network)
            return metadata
        } catch {
            Logger.logError("Failed to parse JSON: \(error)", category: .network)
            // Debug: Show first 500 chars of response
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.logDebug("Raw response (first 500 chars): \(responseString.prefix(500))", category: .network)
            }
            throw AppError.ipfs(.parseFailed(error.localizedDescription))
        }
    }

    /// Download image data from IPFS URL
    /// - Parameter ipfsUrl: IPFS URL string
    /// - Returns: Image data
    /// - Throws: AppError if download fails
    func downloadImageData(from ipfsUrl: String) async throws -> Data {
        Logger.logDebug("Downloading image from: \(ipfsUrl)", category: .network)

        guard let url = URL(string: ipfsUrl) else {
            throw AppError.ipfs(.invalidHash)
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw AppError.ipfs(.downloadFailed("HTTP \(httpResponse.statusCode)"))
            }
        }

        Logger.logDebug("Successfully downloaded image data (\(data.count) bytes)", category: .network)
        return data
    }

    /// Convert IPFS URL to HTTP gateway URL if needed
    /// - Parameter ipfsUrl: IPFS URL, IPFS hash, or HTTP URL
    /// - Returns: HTTP gateway URL
    func convertToHTTPGateway(_ ipfsUrl: String) -> String {
        // If it's already an HTTP/HTTPS URL, return as-is
        if ipfsUrl.hasPrefix("http://") || ipfsUrl.hasPrefix("https://") {
            Logger.logDebug("URL is already HTTP: \(ipfsUrl)", category: .network)
            return ipfsUrl
        }

        // If it's an IPFS URL, convert to gateway
        if ipfsUrl.hasPrefix("ipfs://") {
            let hash = ipfsUrl.replacingOccurrences(of: "ipfs://", with: "")
            return "https://ipfs.io/ipfs/\(hash)"
        }

        // If it starts with a hash-like pattern (Qm..., bafy...), assume it's just a hash
        if ipfsUrl.hasPrefix("Qm") || ipfsUrl.hasPrefix("bafy") || ipfsUrl.hasPrefix("bafk") {
            return "https://ipfs.io/ipfs/\(ipfsUrl)"
        }

        // For anything else, try to use it as-is but log a warning
        Logger.logWarning("Unrecognized URI format: \(ipfsUrl)", category: .network)
        return ipfsUrl
    }
}

