import Foundation
import Observation
import os

/// Manages the downloadable on-device EmbeddingGemma model (LiteRT/Core ML weights + SentencePiece
/// tokenizer). Ports `class EmbeddingModelManager` from `data/embedding/EmbeddingModelManager.kt`.
///
/// The ~180 MB model is **not** bundled in the app; the user opts in to the download. The source repo
/// (`litert-community/embeddinggemma-300m`) is gated under the Gemma license, so an unauthenticated
/// fetch may be rejected. `download(overrideToken:)` accepts an optional bearer token; a 401/403
/// surfaces a clear "gated" hint.
///
/// iOS mapping (DESIGN §6 / CONVENTIONS):
/// - Storage moves from Android's external files dir to **Application Support** (`models/`).
/// - State becomes `@Observable` (`ModelState`) so SwiftUI tracks it directly (replaces `StateFlow`).
/// - Download uses `URLSession.bytes(for:)` streaming to a `.part` file, then an **atomic move** into
///   place (replaces the OkHttp byte-stream + `renameTo`).
/// - Token resolution order is preserved (BYOK): a freshly pasted token wins (persisted only once a
///   download it authenticated has succeeded), then a previously saved token, then `nil` — no token
///   ships in the app bundle.
/// - `MIN_MODEL_BYTES` size floor guards against a truncated / HTML error page being mistaken for the
///   model; the tokenizer is fetched **first** so we fail fast on auth/network before the big file.
///
/// `@MainActor` so the `@Observable` state mutations are isolated to the main actor (the heavy byte
/// streaming happens inside the awaited `URLSession.bytes` calls, off the main thread). The disk
/// helpers are `nonisolated`.
@Observable
@MainActor
final class EmbeddingModelManager {

    /// Mirrors the Kotlin `sealed interface State`.
    enum ModelState: Equatable {
        /// Model files not present — the on-device path is unavailable.
        case absent
        /// Download in progress. `fraction` is 0...1 across both files; `label` is a human note.
        case downloading(fraction: Double, label: String)
        /// Both files present — on-device embedding can run.
        case ready
        case failed(String)
    }

    private let tokenStore: TokenStore
    @ObservationIgnored private nonisolated let logger = Logger(subsystem: "com.curio.app", category: "EmbeddingModelManager")

    /// Observable download/availability state. Seeded from disk at construction.
    private(set) var state: ModelState

    /// Serializes downloads: a double-tapped DOWNLOAD/RETRY, or a trigger from both the Settings
    /// card and the feed sheet, would otherwise run two tasks writing the same ".part" temp file
    /// and both renaming it onto the model path — corrupting the weights on disk. The flag is the
    /// `@MainActor` analogue of the Kotlin `Mutex.tryLock()`: a concurrent re-trigger is ignored
    /// rather than queued behind the in-flight download.
    private var isDownloadInFlight = false

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
        self.state = Self.isReadyOnDisk() ? .ready : .absent
    }

    // MARK: - Disk layout (nonisolated — pure FS helpers)

    /// `Application Support/models/` (created on demand). Mirrors Android's `models` subdir.
    nonisolated static func modelDir() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func modelFileURL() -> URL { modelDir().appendingPathComponent(MODEL_FILE) }
    nonisolated static func tokenizerFileURL() -> URL { modelDir().appendingPathComponent(TOKENIZER_FILE) }

    nonisolated func modelFileURL() -> URL { Self.modelFileURL() }
    nonisolated func tokenizerFileURL() -> URL { Self.tokenizerFileURL() }

    /// True when both the weights and tokenizer are present and non-empty. Port of `isReady()`.
    nonisolated static func isReadyOnDisk() -> Bool {
        let fm = FileManager.default
        let model = modelFileURL()
        let tokenizer = tokenizerFileURL()
        let modelOk = fm.fileExists(atPath: model.path) && fileSize(model) > MIN_MODEL_BYTES
        let tokenizerOk = fm.fileExists(atPath: tokenizer.path) && fileSize(tokenizer) > 0
        return modelOk && tokenizerOk
    }

    /// Instance accessor for `isReady` (used by `EmbeddingAvailability`).
    nonisolated func isReady() -> Bool { Self.isReadyOnDisk() }

    nonisolated static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Re-derive state from disk (e.g. after a side-loaded file). Port of `refresh()`.
    func refresh() {
        state = Self.isReadyOnDisk() ? .ready : .absent
    }

    // MARK: - Download

    /// Downloads the tokenizer (small) then the weights (large), reporting combined progress. Safe to
    /// call again after a failure — partial files are overwritten. Returns `true` on success. Port of
    /// `suspend fun download(overrideToken:)`.
    @discardableResult
    func download(overrideToken: String? = nil) async -> Bool {
        if Self.isReadyOnDisk() {
            state = .ready
            return true
        }

        // Ignore a re-entrant call while a download is already running (see `isDownloadInFlight`).
        // The in-flight task keeps driving `state`, so the UI is unaffected by the ignored tap.
        if isDownloadInFlight {
            logger.debug("Download already in progress; ignoring re-entrant request")
            return false
        }
        isDownloadInFlight = true
        defer { isDownloadInFlight = false }

        // Resolve the HF access token (BYOK): a freshly pasted one wins (and is persisted once the
        // download succeeds, so it's entered once), then a previously saved token. No token ships
        // in the app bundle, so `nil` is possible — fine for an ungated mirror; gated repos surface
        // a clear 401/403 hint below.
        //
        // Trim first: tokens pasted from the HF site routinely carry a trailing newline or spaces.
        // Left intact, that whitespace produces an illegal "Bearer …" header value, so the download
        // dies with a confusing error instead of authenticating — and the tainted value would
        // otherwise be persisted and reused on every retry. Trimming on both the fresh and the
        // saved path also self-heals a previously stored tainted token.
        let pasted = overrideToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let savedToken = await tokenStore.getHuggingFaceToken()?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let authToken: String? = pasted ?? savedToken

        do {
            // Tokenizer first — tiny, lets us fail fast on auth/network before the big file.
            state = .downloading(fraction: 0, label: "Fetching tokenizer…")
            try await fetch(urlString: Self.TOKENIZER_URL, dest: tokenizerFileURL(), authToken: authToken) { _ in }

            try await fetch(urlString: Self.MODEL_URL, dest: modelFileURL(), authToken: authToken) { [weak self] frac in
                self?.state = .downloading(
                    fraction: frac,
                    label: "Downloading model… \(Int(frac * 100))%"
                )
            }

            if Self.isReadyOnDisk() {
                // Persist only a token we've now confirmed works, so a wrong/expired submission
                // can't poison later blank-field retries with a cached bad token.
                if let pasted { await tokenStore.saveHuggingFaceToken(pasted) }
                state = .ready
                return true
            } else {
                cleanup()
                state = .failed("Downloaded files were incomplete")
                return false
            }
        } catch is CancellationError {
            cleanup()
            state = .failed("Download failed")
            return false
        } catch {
            logger.error("Model download failed: \(error.localizedDescription, privacy: .public)")
            cleanup()
            let message = (error as? DownloadError)?.message ?? error.localizedDescription
            let hint: String
            if message.contains("401") || message.contains("403") {
                hint = "Model is gated — a Hugging Face access token is required."
            } else {
                hint = message.isEmpty ? "Download failed" : message
            }
            state = .failed(hint)
            return false
        }
    }

    /// Deletes the model files and resets state. Port of `delete()`.
    func delete() {
        cleanup()
        state = .absent
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: modelFileURL())
        try? FileManager.default.removeItem(at: tokenizerFileURL())
    }

    /// Streams `urlString` to a `.part` file reporting progress, then atomically moves it to `dest`.
    /// Mirrors the Kotlin `fetch(url, dest, authToken, onProgress)`: a non-success status throws an
    /// error whose message embeds the HTTP code (so the 401/403 hint fires), an empty body throws,
    /// and the temp file is renamed (with copy-fallback) into place.
    @MainActor
    private func fetch(
        urlString: String,
        dest: URL,
        authToken: String?,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let url = URL(string: urlString) else {
            throw DownloadError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 300 // generous read timeout for large binaries (5 min in Android)
        if let authToken, !authToken.isBlank {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        // A dedicated session: long resource timeout, no body logging. URLSession is retained by
        // the system until invalidated — without finishTasksAndInvalidate() every download
        // attempt (including each retry) leaked one session for the rest of the process.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadError("No HTTP response for \(urlString)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError("HTTP \(http.statusCode) for \(urlString)")
        }
        let total = http.expectedContentLength // -1 when unknown
        let knownTotal = total > 0 ? Double(total) : nil

        let tmp = dest.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: tmp)
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else {
            throw DownloadError("Cannot open temp file for \(urlString)")
        }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= (1 << 16) {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let knownTotal { onProgress(Double(written) / knownTotal) }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
            if let knownTotal { onProgress(Double(written) / knownTotal) }
        }
        try handle.close()

        // Empty body guard (Kotlin `body ?: throw … "Empty body"`).
        if written == 0 {
            try? FileManager.default.removeItem(at: tmp)
            throw DownloadError("Empty body for \(urlString)")
        }

        // Atomic move into place (Kotlin `renameTo`, with copy+delete fallback).
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            try FileManager.default.copyItem(at: tmp, to: dest)
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    /// Internal download error carrying the message used for the gated-hint substring check.
    private struct DownloadError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    // MARK: - Constants (mirror the Kotlin companion object)

    // `nonisolated` so the pure FS helpers above (also `nonisolated`) can read them; they are
    // immutable `Sendable` constants regardless of the type's `@MainActor` isolation.

    /// Local on-disk names (stable regardless of the remote filename).
    nonisolated static let MODEL_FILE = "embeddinggemma_seq256.tflite"
    nonisolated static let TOKENIZER_FILE = "sentencepiece.model"

    /// ~180 MB; guards against a truncated / HTML error page being mistaken for the model.
    nonisolated static let MIN_MODEL_BYTES: Int64 = 1_000_000

    /// `litert-community/embeddinggemma-300m` — gated under the Gemma license.
    /// The repo renamed the seq256 weights to a `_mixed-precision` suffix; the old
    /// `embeddinggemma-300M_seq256.tflite` path now 404s (mirrors Android `EmbeddingModelManager`).
    nonisolated private static let REPO = "https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main"
    nonisolated static let MODEL_URL = "\(REPO)/embeddinggemma-300M_seq256_mixed-precision.tflite?download=true"
    nonisolated static let TOKENIZER_URL = "\(REPO)/sentencepiece.model?download=true"

    /// Approximate total download size, for the UI.
    nonisolated static let APPROX_SIZE_LABEL = "~180 MB"
}

// MARK: - Blank helper (Kotlin `takeIf { it.isNotEmpty() }`)

private extension String {
    /// `nil` when empty (e.g. a whitespace-only token collapsed by trimming), else the value.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
