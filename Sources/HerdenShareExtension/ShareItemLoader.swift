import Foundation
import UniformTypeIdentifiers

enum ShareItemLoaderError: Error {
    case unsupportedItem
    case copyFailed
}

struct LoadedShareItem: Sendable {
    let url: URL
    let displayName: String
}

@MainActor
enum ShareItemLoader {
    static func load(from extensionContext: NSExtensionContext?) async throws -> LoadedShareItem {
        guard
            let providers = extensionContext?.inputItems
                .compactMap({ $0 as? NSExtensionItem })
                .flatMap({ $0.attachments ?? [] }),
            let provider = providers.first,
            let typeIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
                UTType(identifier)?.conforms(to: .data) == true
            })
        else { throw ShareItemLoaderError.unsupportedItem }

        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url, error == nil else {
                    continuation.resume(throwing: error ?? ShareItemLoaderError.unsupportedItem)
                    return
                }
                let ext = PreparedFile.safeExtension(url.pathExtension)
                let name = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(
                        returning: LoadedShareItem(
                            url: copy,
                            displayName: suggestedName ?? url.lastPathComponent))
                } catch {
                    continuation.resume(throwing: ShareItemLoaderError.copyFailed)
                }
            }
        }
    }
}
