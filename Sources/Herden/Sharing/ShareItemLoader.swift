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
        let providers = extensionContext?.inputItems
                .compactMap({ $0 as? NSExtensionItem })
                .flatMap({ $0.attachments ?? [] }) ?? []
        return try await load(providers: providers)
    }

    static func load(providers: [NSItemProvider]) async throws -> LoadedShareItem {
        // Apps such as Discord commonly add a caption or source URL beside the
        // actual image. Treat those providers as metadata instead of rejecting
        // an otherwise valid one-file share.
        let fileProviders = providers.filter(isFileProvider)
        guard fileProviders.count == 1, let provider = fileProviders.first else {
            throw ShareItemLoaderError.unsupportedItem
        }
        if let typeIdentifier = preferredTypeIdentifier(for: provider) {
            do { return try await loadFile(provider, typeIdentifier: typeIdentifier) }
            catch {
                guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { throw error }
            }
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            throw ShareItemLoaderError.unsupportedItem
        }
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                do {
                    if let error { throw error }
                    guard let url = item as? URL, url.isFileURL else { throw ShareItemLoaderError.unsupportedItem }
                    continuation.resume(returning: try copy(url, suggestedName: suggestedName))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func isFileProvider(_ provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return true
        }
        return provider.registeredTypeIdentifiers.contains { identifier in
            guard let type = UTType(identifier) else { return false }
            if type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .audio) {
                return true
            }
            return type.conforms(to: .data)
                && !type.conforms(to: .url)
                && !type.conforms(to: .text)
        }
    }

    private static func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        let identifiers = provider.registeredTypeIdentifiers
        let types = identifiers.compactMap { identifier -> (String, UTType)? in
            guard let type = UTType(identifier),
                  type.conforms(to: .data),
                  !type.conforms(to: .url) else { return nil }
            return (identifier, type)
        }
        return types.first(where: { _, type in
            type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .audio)
        })?.0 ?? types.first(where: { _, type in
            !type.conforms(to: .text)
        })?.0 ?? types.first?.0
    }

    private static func loadFile(_ provider: NSItemProvider, typeIdentifier: String) async throws -> LoadedShareItem {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                guard let url, error == nil else {
                    continuation.resume(throwing: error ?? ShareItemLoaderError.unsupportedItem)
                    return
                }
                do {
                    continuation.resume(returning: try copy(url, suggestedName: suggestedName))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// The provider owns the input URL only for the duration of its callback.
    /// Copy in bounded chunks here, including file-URL-only providers from Files.
    private nonisolated static func copy(_ url: URL, suggestedName: String?) throws -> LoadedShareItem {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ShareItemLoaderError.unsupportedItem }
        guard let size = values.fileSize, size > 0 else { throw ShareItemLoaderError.unsupportedItem }
        guard size <= FilePreparer.maximumByteCount else { throw FilePreparationError.sourceTooLarge }
        let ext = PreparedFile.safeExtension(url.pathExtension)
        let name = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard FileManager.default.createFile(atPath: target.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else {
            throw ShareItemLoaderError.copyFailed
        }
        do {
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }
            var total = 0
            while let data = try input.read(upToCount: 262_144), !data.isEmpty {
                total += data.count
                guard total <= FilePreparer.maximumByteCount else { throw FilePreparationError.sourceTooLarge }
                try output.write(contentsOf: data)
            }
            guard total > 0 else { throw ShareItemLoaderError.unsupportedItem }
            return LoadedShareItem(url: target, displayName: suggestedName ?? url.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }
}
