import Foundation
import CoreML
import os

/// A pluggable text-embedding backend. Like `TextGenerator` for generation, this protocol is what
/// gets injected so the on-device and cloud embedding paths are fully interchangeable and the
/// on-device path can be device-gated. Ports `interface EmbeddingProvider` from
/// `data/embedding/EmbeddingProvider.kt`.
///
/// `embedDocument` / `embedQuery` are plain `suspend` (no `Result`) → `async` with **no** `throws`
/// (CONVENTIONS §3): they return `nil` on any failure, never throw. `Sendable` because providers
/// cross actor boundaries (CONVENTIONS §5).
protocol EmbeddingProvider: Sendable {
    func embedDocument(_ bookmark: Bookmark) async -> [Float]?
    func embedQuery(_ query: String) async -> [Float]?
    /// True when embeddings are computed on-device (no network / fully private).
    func isOnDevice() -> Bool
    /// Reason the most recent embed returned nil (for the UI), or nil if none/not tracked.
    var lastError: String? { get }
}

extension EmbeddingProvider {
    var lastError: String? { nil }
}

/// Shared document-text assembly so on-device and cloud embed the *same* text for a bookmark.
/// Ports `object EmbeddingText`. Caseless namespace enum (CONVENTIONS §1).
///
/// CONVENTIONS §10 char-count note: Kotlin `take(n)` counts UTF-16 code units; Swift `prefix(n)` on
/// `Character` counts grapheme clusters. For the texts involved (assembled summaries/abstracts) the
/// difference is negligible and the assembled text is not a byte-format-sensitive path.
enum EmbeddingText {
    /// seq256 on-device weights: 256 tokenizer positions incl. task prefix; clip before inference.
    static let maxEmbedChars = 480
    /// Larger chunks for the cloud embedder (xAI accepts up to ~8k chars per call).
    static let cloudChunkChars = 800
    static let minEmbedChars = 64
    private static let MAX_CHUNKS = 4

    static func isTokenLimitError(_ error: Error) -> Bool {
        var current: Error? = error
        while let e = current {
            let msg = String(describing: e)
            if msg.localizedCaseInsensitiveContains("max_input_size") ||
                msg.localizedCaseInsensitiveContains("token.size()") {
                return true
            }
            if let ns = e as NSError?,
               let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
                current = underlying
            } else {
                break
            }
        }
        return false
    }

    /// Hard cap applied immediately before each on-device inference (queries + document chunks).
    static func clipForOnDevice(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxEmbedChars))
    }

    /// Single-vector document text (header signals + truncated body). Port of `forDocument(b)`.
    /// Falls back to the raw tweet text when the assembled string is blank.
    static func forDocument(_ b: Bookmark) -> String {
        var sb = ""
        if let t = b.sourceTitle { sb += t; sb += ". " }
        if let a = b.sourceAbstract { sb += String(a.prefix(1000)); sb += " " }
        if let s = b.summary { sb += s; sb += " " }
        if !b.tags.isEmpty { sb += b.tags.joined(separator: " "); sb += " " }
        if let e = b.entities {
            sb += String(e.replacing(entityStripRegex, with: " ").prefix(200)); sb += " "
        }
        sb += String(b.text.prefix(500))
        let trimmed = sb.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? b.text : trimmed
    }

    /// Splits a document into up to `MAX_CHUNKS` retrieval chunks so long papers don't lose their body
    /// content. Chunk 1 is the high-signal header (title + abstract + summary + tags); the rest window
    /// over the body. Port of `chunksForDocument(b)`.
    static func chunksForDocument(_ b: Bookmark, chunkChars: Int = maxEmbedChars) -> [String] {
        let safeChunk = max(chunkChars, minEmbedChars)
        var headerSb = ""
        if let t = b.sourceTitle { headerSb += t; headerSb += ". " }
        if let a = b.sourceAbstract { headerSb += a; headerSb += " " }
        if let s = b.summary { headerSb += s; headerSb += " " }
        if !b.tags.isEmpty { headerSb += b.tags.joined(separator: " "); headerSb += " " }
        let header = headerSb.trimmingCharacters(in: .whitespacesAndNewlines)

        var chunks: [String] = []
        if !header.isEmpty { chunks.append(String(header.prefix(safeChunk))) }

        let body = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Index by UTF-16 offsets to mirror Kotlin's `substring(i, min(i+chunkChars, length))`
        // (Kotlin String indexing is UTF-16 code-unit based).
        let scalarsView = Array(body.utf16)
        var i = 0
        while i < scalarsView.count && chunks.count < MAX_CHUNKS {
            let end = min(i + safeChunk, scalarsView.count)
            let slice = Array(scalarsView[i..<end])
            let chunk = String(utf16CodeUnits: slice, count: slice.count)
            chunks.append(chunk)
            i += safeChunk
        }
        return chunks.isEmpty ? [String(forDocument(b).prefix(safeChunk))] : chunks
    }

    /// Element-wise mean of per-chunk vectors → one document vector. Vectors of a differing dimension
    /// are not pooled (returns the first), guarding against mixing incompatible embedding sizes.
    /// Port of `meanPool(vectors)`.
    static func meanPool(_ vectors: [[Float]]) -> [Float]? {
        let nonEmpty = vectors.filter { !$0.isEmpty }
        if nonEmpty.isEmpty { return nil }
        let dim = nonEmpty[0].count
        if nonEmpty.contains(where: { $0.count != dim }) { return nonEmpty[0] }
        var acc = [Float](repeating: 0, count: dim)
        for v in nonEmpty {
            for j in 0..<dim { acc[j] += v[j] }
        }
        let n = Float(nonEmpty.count)
        for j in 0..<dim { acc[j] /= n }
        return acc
    }

    /// `[\"{}\[\]]` — strips JSON punctuation from the entities blob before embedding.
    private nonisolated(unsafe) static let entityStripRegex = /["{}\[\]]/
}

/// Detects whether the on-device EmbeddingGemma model is present. Availability reduces to "have the
/// weights + tokenizer been downloaded?", which `EmbeddingModelManager` answers. Ports
/// `class EmbeddingAvailability`.
struct EmbeddingAvailability: Sendable {
    private let modelManager: EmbeddingModelManager

    init(modelManager: EmbeddingModelManager) {
        self.modelManager = modelManager
    }

    /// True when the model files are present on disk. Reads the FS directly (the manager's disk check
    /// is `nonisolated static`), so this is safe to call synchronously from any isolation.
    func isEmbeddingGemmaAvailable() -> Bool {
        EmbeddingModelManager.isReadyOnDisk()
    }
}

/// On-device EmbeddingGemma backend. Ports `class OnDeviceEmbeddingProvider`.
///
/// Android ran EmbeddingGemma through the AI Edge RAG `GeckoEmbeddingModel` (LiteRT weights +
/// SentencePiece tokenizer). On iOS the downloaded `.tflite` is converted to a Core ML `.mlpackage`
/// and loaded lazily; a single `MLModel` wraps one interpreter that is **not** safe to invoke
/// concurrently, so inference is serialized by making this an `actor` (CONVENTIONS §5 — the actor
/// replaces the Kotlin `Mutex inferenceLock`).
///
/// EmbeddingGemma is task-aware: documents are embedded with the `RETRIEVAL_DOCUMENT` task prefix and
/// queries with `RETRIEVAL_QUERY` so query/document vectors align. Inference runs on **CPU**
/// (`computeUnits = .cpuOnly`): the GPU/ANE path is known to emit all-zero vectors unless precision is
/// forced to FP32, so CPU is the safe default (CONVENTIONS §6 "CPU only").
///
/// Gated by `EmbeddingAvailability`: returns `nil` when the model isn't downloaded so the selector
/// falls back to the cloud provider.
actor OnDeviceEmbeddingProvider: EmbeddingProvider {

    private let availability: EmbeddingAvailability
    private let modelManager: EmbeddingModelManager
    private static let logger = Logger(subsystem: "com.curio.app", category: "OnDeviceEmbedding")

    /// Thread-safe slot for the last inference error (read synchronously by the selector/VM).
    private final class ErrorSlot: @unchecked Sendable {
        private let lock = NSLock()
        var value: String?
        func set(_ v: String?) {
            lock.lock()
            defer { lock.unlock() }
            value = v
        }
        func get() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private let lastErrorSlot = ErrorSlot()

    nonisolated var lastError: String? { lastErrorSlot.get() }

    /// EmbeddingGemma task prefixes (the model is task-aware; these mirror the LiteRT
    /// `EmbedData.TaskType` values used on Android).
    private enum TaskType {
        static let document = "task: search result | query: "
        static let query = "task: question answering | query: "
    }

    /// Lazily-loaded Core ML model. Loaded once; cleared by `release()`.
    private var model: MLModel?
    /// Compiled model URL cache so the `.mlmodelc` is compiled only once per process.
    private var compiledURL: URL?

    init(availability: EmbeddingAvailability, modelManager: EmbeddingModelManager) {
        self.availability = availability
        self.modelManager = modelManager
    }

    /// Synchronous availability — reads the FS via `EmbeddingAvailability`. `nonisolated` so callers
    /// (the selector) can gate without awaiting the actor. Port of `isOnDevice()`.
    nonisolated func isOnDevice() -> Bool {
        availability.isEmbeddingGemmaAvailable()
    }

    /// Chunks long documents and mean-pools the per-chunk vectors so body content is retained.
    /// Port of `embedDocument(bookmark)`.
    func embedDocument(_ bookmark: Bookmark) async -> [Float]? {
        guard availability.isEmbeddingGemmaAvailable() else {
            lastErrorSlot.set("On-device EmbeddingGemma model not downloaded (Settings → Download model).")
            return nil
        }
        var vectors: [[Float]] = []
        for chunk in EmbeddingText.chunksForDocument(bookmark) {
            if let v = await embed(chunk, task: TaskType.document) { vectors.append(v) }
        }
        let pooled = EmbeddingText.meanPool(vectors)
        if pooled != nil {
            lastErrorSlot.set(nil)
        } else if lastErrorSlot.get() == nil {
            lastErrorSlot.set("On-device embedding returned no vector.")
        }
        return pooled
    }

    func embedQuery(_ query: String) async -> [Float]? {
        await embed(query, task: TaskType.query)
    }

    // MARK: - Inference (serialized by actor isolation)

    /// Ensures the Core ML model is loaded, returning nil when the files are absent or load fails.
    /// Mirrors the Kotlin `ensureModel()` double-checked lazy construction (the actor serializes it).
    private func ensureModel() async -> MLModel? {
        if let model { return model }
        guard availability.isEmbeddingGemmaAvailable() else { return nil }
        let modelPath = modelManager.modelFileURL()
        // LiteRT `.tflite` weights (what we download from Hugging Face) cannot be passed to
        // `MLModel.compileModel` — iOS needs a pre-converted Core ML bundle (`encoder.mlmodelc`).
        if modelPath.pathExtension.lowercased() == "tflite" {
            let msg = "On-device embedding on iOS requires a Core ML model bundle, not LiteRT (.tflite) weights. Delete the model in Settings — a Core ML download path is not wired up yet; use Embedding engine → Auto until then."
            lastErrorSlot.set(msg)
            Self.logger.error("\(msg, privacy: .public)")
            return nil
        }
        do {
            let config = MLModelConfiguration()
            // CPU only — the GPU/ANE path emits zero vectors unless precision is FP32.
            config.computeUnits = .cpuOnly

            // The downloaded weights are a Core ML package (`.mlpackage`) converted from the `.tflite`.
            // Compile once and cache the compiled `.mlmodelc` URL. The async `compileModel(at:)`
            // overload is the supported form (the synchronous one is deprecated and runs off the
            // main thread anyway); the actor keeps the compile serialized.
            let compiled: URL
            if let cached = compiledURL {
                compiled = cached
            } else {
                compiled = try await MLModel.compileModel(at: modelPath)
                compiledURL = compiled
            }
            let loaded = try MLModel(contentsOf: compiled, configuration: config)
            model = loaded
            return loaded
        } catch {
            Self.logger.error("Failed to load EmbeddingGemma: \(error.localizedDescription, privacy: .public)")
            lastErrorSlot.set("On-device model load failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Runs one embedding inference for `text` with the given task prefix; returns nil on any failure
    /// or an empty vector. Serialized by actor isolation (one interpreter, no concurrency). Port of
    /// the private `embed(text, task)`.
    private func embed(_ text: String, task: String) async -> [Float]? {
        guard let model = await ensureModel() else { return nil }
        let clipped = EmbeddingText.clipForOnDevice(text)
        if clipped.isEmpty { return nil }
        do {
            let prefixed = task + clipped
            // The converted model takes a single string feature named `text` and emits a
            // `MLMultiArray` named `embedding`. (Names follow the standard EmbeddingGemma conversion.)
            let input = try MLDictionaryFeatureProvider(dictionary: ["text": prefixed])
            let output = try runPrediction(model, from: input)
            guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
                let msg = "EmbeddingGemma produced no embedding feature"
                lastErrorSlot.set(msg)
                Self.logger.warning("\(msg, privacy: .public)")
                return nil
            }
            let count = array.count
            if count == 0 {
                let msg = "On-device EmbeddingGemma returned an empty vector."
                lastErrorSlot.set(msg)
                Self.logger.warning("\(msg, privacy: .public)")
                return nil
            }
            var vector = [Float](repeating: 0, count: count)
            for i in 0..<count {
                vector[i] = array[i].floatValue
            }
            lastErrorSlot.set(nil)
            return vector
        } catch {
            let msg = "On-device embed failed: \(error.localizedDescription)"
            lastErrorSlot.set(msg)
            Self.logger.error("\(msg, privacy: .public)")
            return nil
        }
    }

    /// Synchronous CoreML inference, kept on the actor so the non-`Sendable` `MLModel` is never sent
    /// to the nonisolated `async` `prediction` overload. Calling from this non-`async` context binds to
    /// the synchronous `prediction(from:)` and runs serialized on the actor (the interpreter is not
    /// concurrency-safe — see the type doc).
    private func runPrediction(_ model: MLModel, from input: MLFeatureProvider) throws -> MLFeatureProvider {
        try model.prediction(from: input)
    }

    /// Releases the loaded model. Port of `release()`. Call when the model file is deleted.
    func release() {
        model = nil
        compiledURL = nil
    }
}

/// Routes embedding requests to EmbeddingGemma on-device or the cloud provider, honouring the user's
/// `EmbeddingBackend` choice (`backend` is read on every call so a Settings change takes effect
/// immediately). Ports `class EmbeddingProviderSelector`.
struct EmbeddingProviderSelector: EmbeddingProvider {
    private let onDevice: OnDeviceEmbeddingProvider
    private let cloud: EmbeddingProvider
    private let backend: @Sendable () -> EmbeddingBackend

    init(
        onDevice: OnDeviceEmbeddingProvider,
        cloud: EmbeddingProvider,
        backend: @escaping @Sendable () -> EmbeddingBackend = { EmbeddingPreference.get() }
    ) {
        self.onDevice = onDevice
        self.cloud = cloud
        self.backend = backend
    }

    func isOnDevice() -> Bool {
        switch backend() {
        case .onDevice: return true
        case .xai: return false
        case .auto: return onDevice.isOnDevice()
        }
    }

    var lastError: String? {
        onDevice.lastError ?? cloud.lastError
    }

    func embedDocument(_ bookmark: Bookmark) async -> [Float]? {
        switch backend() {
        case .onDevice:
            return await onDevice.embedDocument(bookmark)
        case .xai:
            return await cloud.embedDocument(bookmark)
        case .auto:
            if onDevice.isOnDevice() {
                // `await` can't sit on the right of `??` (autoclosure); expand it.
                if let v = await onDevice.embedDocument(bookmark) { return v }
                return await cloud.embedDocument(bookmark)
            }
            return await cloud.embedDocument(bookmark)
        }
    }

    func embedQuery(_ query: String) async -> [Float]? {
        switch backend() {
        case .onDevice:
            return await onDevice.embedQuery(query)
        case .xai:
            return await cloud.embedQuery(query)
        case .auto:
            if onDevice.isOnDevice() {
                // `await` can't sit on the right of `??` (autoclosure); expand it.
                if let v = await onDevice.embedQuery(query) { return v }
                return await cloud.embedQuery(query)
            }
            return await cloud.embedQuery(query)
        }
    }
}
