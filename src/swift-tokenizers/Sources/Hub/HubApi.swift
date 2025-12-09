//
//  HubApi.swift
//
//
//  Created by Pedro Cuenca on 20231230.
//

import Foundation

public struct HubApi {
    var downloadBase: URL
    var hfToken: String?
    var endpoint: String
    var useBackgroundSession: Bool

    public typealias RepoType = Hub.RepoType
    public typealias Repo = Hub.Repo

    public init(downloadBase: URL? = nil, hfToken: String? = nil, endpoint: String = "https://huggingface.co", useBackgroundSession: Bool = false) {
        self.hfToken = hfToken ?? Self.hfTokenFromEnv()
        if let downloadBase {
            self.downloadBase = downloadBase
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.downloadBase = documents.appending(component: "huggingface")
        }
        self.endpoint = endpoint
        self.useBackgroundSession = useBackgroundSession
    }

    public static let shared = HubApi()
}

private extension HubApi {
    static func hfTokenFromEnv() -> String? {
        let possibleTokens = [
            { ProcessInfo.processInfo.environment["HF_TOKEN"] },
            { ProcessInfo.processInfo.environment["HUGGING_FACE_HUB_TOKEN"] },
            {
                ProcessInfo.processInfo.environment["HF_TOKEN_PATH"].flatMap {
                    try? String(
                        contentsOf: URL(filePath: NSString(string: $0).expandingTildeInPath),
                        encoding: .utf8
                    )
                }
            },
            {
                ProcessInfo.processInfo.environment["HF_HOME"].flatMap {
                    try? String(
                        contentsOf: URL(filePath: NSString(string: $0).expandingTildeInPath).appending(path: "token"),
                        encoding: .utf8
                    )
                }
            },
            { try? String(contentsOf: .homeDirectory.appendingPathComponent(".cache/huggingface/token"), encoding: .utf8) },
            { try? String(contentsOf: .homeDirectory.appendingPathComponent(".huggingface/token"), encoding: .utf8) }
        ]
        return possibleTokens
            .lazy
            .compactMap({ $0() })
            .filter({ !$0.isEmpty })
            .first
    }
}

/// File retrieval
public extension HubApi {
    /// Model data for parsed filenames
    struct Sibling: Codable {
        let rfilename: String
    }
    
    struct SiblingsResponse: Codable {
        let siblings: [Sibling]
    }
}

/// Additional Errors
public extension HubApi {
    enum EnvironmentError: LocalizedError {
        case invalidMetadataError(String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidMetadataError(let message):
                return message
            }
        }
    }
}

/// Configuration loading helpers
public extension HubApi {
    /// Assumes the file has already been downloaded.
    /// `filename` is relative to the download base.
    func configuration(from filename: String, in repo: Repo) throws -> Config {
        let fileURL = localRepoLocation(repo).appending(path: filename)
        return try configuration(fileURL: fileURL)
    }
    
    /// Assumes the file is already present at local url.
    /// `fileURL` is a complete local file path for the given model
    func configuration(fileURL: URL) throws -> Config {
        let data = try Data(contentsOf: fileURL)
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = parsed as? [NSString: Any] else { throw Hub.HubClientError.parse }
        return Config(dictionary)
    }
}

/// Snaphsot download
public extension HubApi {
    func localRepoLocation(_ repo: Repo) -> URL {
        downloadBase.appending(component: repo.type.rawValue).appending(component: repo.id)
    }
}

/// Metadata
public extension HubApi {
    /// Data structure containing information about a file versioned on the Hub
    struct FileMetadata {
        /// The commit hash related to the file
        public let commitHash: String?
        
        /// Etag of the file on the server
        public let etag: String?
        
        /// Location where to download the file. Can be a Hub url or not (CDN).
        public let location: String
        
        /// Size of the file. In case of an LFS file, contains the size of the actual LFS file, not the pointer.
        public let size: Int?
    }
    
    /// Metadata about a file in the local directory related to a download process
    struct LocalDownloadFileMetadata {
        /// Commit hash of the file in the repo
        public let commitHash: String
        
        /// ETag of the file in the repo. Used to check if the file has changed.
        /// For LFS files, this is the sha256 of the file. For regular files, it corresponds to the git hash.
        public let etag: String
        
        /// Path of the file in the repo
        public let filename: String
        
        /// The timestamp of when the metadata was saved i.e. when the metadata was accurate
        public let timestamp: Date
    }

    private func normalizeEtag(_ etag: String?) -> String? {
        guard let etag = etag else { return nil }
        return etag.trimmingPrefix("W/").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}
