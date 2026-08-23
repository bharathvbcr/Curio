//
//  ShareViewController.swift
//  CurioShareExtension
//
//  Share Extension receiver — the iOS analogue of the Android `MainActivity.handleSendIntent`
//  (`Intent.ACTION_SEND`, `text/plain`) path. Where Android combines the optional share
//  *subject* (e.g. an article title) with the shared *body* and routes it straight through
//  `BookmarkViewModel.captureSharedText(...)`, iOS runs the share sheet in a **separate
//  process** that cannot touch the main app's ViewModel / SwiftData store. So this extension
//  only ever does the cheap, side-effect-free half of the work:
//
//    1. Extract the shared URL(s) and/or plain text from the `NSItemProvider` attachments.
//    2. Reassemble the exact same "subject\nbody" payload string Android builds
//       (filter empty → `distinct` → join with "\n" → `trim`).
//    3. Append it to a FIFO queue in the **App-Group** `UserDefaults` (`pendingShares`).
//    4. Complete the extension request immediately.
//
//  The main app drains `pendingShares` on `scenePhase == .active` (see `CurioApp` /
//  `AppEnvironment` → `BookmarkViewModel.captureSharedText`), which performs all the real
//  ingestion (URL/title extraction, persist, primary-source resolution, cloud mirror) or
//  defers it until sign-in. Per DEPENDENCIES.md the extension does **no** Firestore / AI /
//  network work — it has a tight memory / wall-clock budget and is purely a queue producer.
//
//  CONVENTIONS honored:
//   • Persistence-key stability — the App-Group suite name and `pendingShares` key are a
//     stable wire contract shared with the main app's drain; never rename.
//   • Secret/log hygiene — nothing here logs Authorization or bodies; payloads are user text
//     only and never logged.
//   • iOS-26-only APIs gated behind `#available` with a documented fallback.
//

import UIKit
import UniformTypeIdentifiers
import CoreTransferable

/// Receives `public.url` / `public.plain-text` shares (X app, browsers, readers, …),
/// rebuilds the Android `subject\nbody` payload, and enqueues it for the main app.
///
/// Declared as the `NSExtensionPrincipalClass` in the extension `Info.plist`
/// (`$(PRODUCT_MODULE_NAME).ShareViewController`).
final class ShareViewController: UIViewController {

    // MARK: - App-Group hand-off contract (shared with the main app's drain)

    /// App Group identifier — MUST match `CurioShareExtension.entitlements` *and*
    /// the main app's `Curio.entitlements` (`group.com.curio.app`). Renaming this
    /// silently breaks the share hand-off.
    static let appGroupIdentifier = "group.com.curio.app"

    /// Key under which the FIFO array of pending shared-text payloads lives in the
    /// App-Group `UserDefaults`. The main app reads + clears this on `.active` and
    /// feeds each entry through `BookmarkViewModel.captureSharedText(_:)`.
    static let pendingSharesKey = "pendingShares"

    // MARK: - Type identifiers we accept (mirrors the Info.plist activation rule)

    private static let urlType = UTType.url.identifier         // "public.url"
    private static let plainTextType = UTType.plainText.identifier  // "public.plain-text"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // No custom compose UI: this is a frictionless "tap → saved" capture, matching
        // Android's silent ingest + Toast. We process attachments and dismiss.
        handleSharedItems()
    }

    // MARK: - Extraction

    private func handleSharedItems() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { ($0.attachments ?? []) }

        guard !providers.isEmpty else {
            complete()
            return
        }

        // Each provider yields at most one "fragment": a URL absoluteString or a plain-text
        // string. We collect them in arrival order, then assemble the payload exactly the way
        // Android's `handleSendIntent` does. A single share can carry several attachments
        // (e.g. a title text + a URL), so we await all of them via a dispatch group before
        // building the payload.
        let group = DispatchGroup()
        // `fragments[i]` preserves provider order; nil = no usable value from that provider.
        var fragments = [String?](repeating: nil, count: providers.count)
        // Serialize writes to `fragments` from the completion callbacks (which fire on
        // arbitrary queues) so we never race on the array.
        let lock = NSLock()

        for (index, provider) in providers.enumerated() {
            group.enter()
            loadFragment(from: provider) { value in
                if let value {
                    lock.lock()
                    fragments[index] = value
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let payload = Self.assemblePayload(from: fragments.compactMap { $0 })
            if let payload, !payload.isEmpty {
                Self.enqueue(payload: payload)
            }
            self.complete()
        }
    }

    /// Loads a single textual fragment (a URL's absolute string or plain text) from one
    /// provider. URL is preferred over plain text when a provider conforms to both (so a
    /// browser share surfaces the canonical link rather than a possibly-truncated preview).
    /// Never throws — any failure resolves to `nil` (resilience contract).
    private func loadFragment(from provider: NSItemProvider,
                              completion: @escaping (String?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(Self.urlType) {
            loadURL(from: provider) { url in
                if let url {
                    completion(url.absoluteString)
                } else {
                    // Fall back to plain text if the URL load failed but text is available.
                    self.loadPlainText(from: provider, completion: completion)
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(Self.plainTextType) {
            loadPlainText(from: provider, completion: completion)
        } else {
            completion(nil)
        }
    }

    private func loadURL(from provider: NSItemProvider,
                         completion: @escaping (URL?) -> Void) {
        // `loadTransferable(type:)` (iOS 16+) is the modern path; gate the iOS-26 build behind
        // availability for documentation parity and fall back to the legacy `loadItem` API.
        if #available(iOS 16.0, *) {
            _ = provider.loadTransferable(type: URL.self) { result in
                switch result {
                case .success(let url):
                    completion(url)
                case .failure:
                    completion(nil)
                }
            }
        } else {
            provider.loadItem(forTypeIdentifier: Self.urlType, options: nil) { item, _ in
                if let url = item as? URL {
                    completion(url)
                } else if let data = item as? Data,
                          let str = String(data: data, encoding: .utf8),
                          let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func loadPlainText(from provider: NSItemProvider,
                               completion: @escaping (String?) -> Void) {
        provider.loadItem(forTypeIdentifier: Self.plainTextType, options: nil) { item, _ in
            if let text = item as? String {
                completion(text)
            } else if let url = item as? URL {
                completion(url.absoluteString)
            } else if let data = item as? Data,
                      let str = String(data: data, encoding: .utf8) {
                completion(str)
            } else {
                completion(nil)
            }
        }
    }

    // MARK: - Payload assembly (byte-faithful to Android `handleSendIntent`)

    /// Rebuilds the Android payload:
    /// ```kotlin
    /// listOf(subject, body)
    ///   .filter { it.isNotEmpty() }
    ///   .distinct()
    ///   .joinToString("\n")
    ///   .trim()
    /// ```
    /// On iOS we do not have a strict subject/body split — each provider hands us one
    /// fragment — so we apply the same pipeline over *all* collected fragments in order:
    /// trim each, drop empties, drop later duplicates (order-preserving `distinct`),
    /// join with "\n", then trim the whole. Returns `nil` when nothing usable remains
    /// (the "Nothing to save" case — the extension just dismisses with no enqueue).
    static func assemblePayload(from fragments: [String]) -> String? {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in fragments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }      // .filter { isNotEmpty }
            guard !seen.contains(trimmed) else { continue } // .distinct()
            seen.insert(trimmed)
            ordered.append(trimmed)
        }
        let payload = ordered.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) // outer .trim()
        return payload.isEmpty ? nil : payload
    }

    // MARK: - Enqueue into the App Group

    /// Appends `payload` to the App-Group `pendingShares` FIFO queue. The main app drains and
    /// clears this on `.active`. We re-read → append → write so concurrent shares (rare, but a
    /// user can fire several in quick succession before the app foregrounds) accumulate rather
    /// than clobber. Best-effort: if the suite is unavailable the share is silently dropped
    /// (no crash inside the extension sandbox).
    static func enqueue(payload: String) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        var queue = defaults.stringArray(forKey: pendingSharesKey) ?? []
        queue.append(payload)
        defaults.set(queue, forKey: pendingSharesKey)
    }

    // MARK: - Completion

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
