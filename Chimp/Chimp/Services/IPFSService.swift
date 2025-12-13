//
//  IPFSService.swift
//  Chimp
//
//  Service for downloading NFT metadata from IPFS
//

import Foundation

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

class IPFSService {
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
    /// - Throws: IPFSError if download or parsing fails
    func downloadNFTMetadata(from ipfsUrl: String) async throws -> NFTMetadata {
        print("IPFSService: Downloading NFT metadata from: \(ipfsUrl)")

        guard let url = URL(string: ipfsUrl) else {
            throw IPFSError.invalidURL(ipfsUrl)
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw IPFSError.httpError(httpResponse.statusCode)
            }
        }

        // Parse JSON
        let decoder = JSONDecoder()
        do {
            let metadata = try decoder.decode(NFTMetadata.self, from: data)
            print("IPFSService: Successfully parsed NFT metadata")
            print("IPFSService: Name: \(metadata.name ?? "N/A")")
            print("IPFSService: Description: \(metadata.description ?? "N/A")")
            print("IPFSService: Image: \(metadata.image ?? "N/A")")
            return metadata
        } catch {
            print("IPFSService: Failed to parse JSON: \(error)")
            throw IPFSError.invalidJSON(error.localizedDescription)
        }
    }

    /// Download image data from IPFS URL
    /// - Parameter ipfsUrl: IPFS URL string
    /// - Returns: Image data
    /// - Throws: IPFSError if download fails
    func downloadImageData(from ipfsUrl: String) async throws -> Data {
        print("IPFSService: Downloading image from: \(ipfsUrl)")

        guard let url = URL(string: ipfsUrl) else {
            throw IPFSError.invalidURL(ipfsUrl)
        }

        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw IPFSError.httpError(httpResponse.statusCode)
            }
        }

        print("IPFSService: Successfully downloaded image data (\(data.count) bytes)")
        return data
    }

    /// Convert IPFS URL to HTTP gateway URL if needed
    /// - Parameter ipfsUrl: IPFS URL or IPFS hash
    /// - Returns: HTTP gateway URL
    func convertToHTTPGateway(_ ipfsUrl: String) -> String {
        if ipfsUrl.hasPrefix("ipfs://") {
            let hash = ipfsUrl.replacingOccurrences(of: "ipfs://", with: "")
            return "https://ipfs.io/ipfs/\(hash)"
        } else if ipfsUrl.hasPrefix("https://ipfs.io/ipfs/") {
            return ipfsUrl
        } else {
            // Assume it's just a hash and prepend gateway
            return "https://ipfs.io/ipfs/\(ipfsUrl)"
        }
    }
}

enum IPFSError: Error, LocalizedError {
    case invalidURL(String)
    case httpError(Int)
    case invalidJSON(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid IPFS URL: \(url)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .invalidJSON(let details):
            return "Invalid JSON format: \(details)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
