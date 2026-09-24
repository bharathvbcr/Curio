import Foundation
import ImageIO
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// On-device OCR via the Vision framework. Ports `class OcrAnalyzer` from `data/ocr/OcrAnalyzer.kt`.
///
/// The Android implementation used ML Kit's Latin text recognizer wrapped in a
/// `suspendCancellableCoroutine` that **never throws** — every failure path resumes with a
/// human-readable fallback string. This port preserves that contract exactly (CONVENTIONS §3
/// "Resilience contract" — OCR logs + returns a fallback string, never throws) and the three exact
/// user-facing fallback strings:
/// - blank result → `"No text detected in selected image."`
/// - recognition failure → `"OCR failed to process: <localizedDescription>"`
/// - image/bitmap load error → `"Bitmap load error: <message>"`
///
/// iOS mapping (DESIGN tech-table "ML Kit Latin text recognition → Vision `RecognizeTextRequest`"):
/// the iOS 18+ async `RecognizeTextRequest` is used with `.accurate` recognition level and the
/// language constrained to English (`["en"]`), matching the ML Kit Latin recognizer.
final class OcrAnalyzer: Sendable {

    init() {}

    /// Recognizes text in image bytes. Never throws. A missing bitmap returns the same fallback
    /// string as a failed `UIImage`/`Bitmap` load.
    func analyze(imageData: Data) async -> String {
        guard let cgImage = Self.cgImage(from: imageData) else {
            return "Bitmap load error: no underlying image data"
        }
        return await analyze(cgImage: cgImage)
    }

    #if canImport(UIKit)
    /// Recognizes text in `image`, returning the joined recognized strings or one of the fallback
    /// strings above. Never throws. Plain `suspend` → `async` (no throws), per CONVENTIONS §3.
    func analyze(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else {
            return "Bitmap load error: no underlying image data"
        }
        return await analyze(cgImage: cgImage)
    }
    #endif

    private func analyze(cgImage: CGImage) async -> String {
        if #available(iOS 26, macOS 26, *) {
            return await recognizeModern(cgImage)
        } else {
            return await recognizeLegacy(cgImage)
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - iOS 26+ / macOS 26+ async RecognizeTextRequest

    @available(iOS 26, macOS 26, *)
    private func recognizeModern(_ cgImage: CGImage) async -> String {
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [Locale.Language(identifier: "en")]
            request.usesLanguageCorrection = true
            let observations = try await request.perform(on: cgImage)
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            // Kotlin: `if (text.isBlank()) "No text detected…" else text`.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "No text detected in selected image."
            }
            return text
        } catch {
            // Mirror ML Kit's `addOnFailureListener { … e.localizedMessage }`.
            return "OCR failed to process: \(error.localizedDescription)"
        }
    }

    // MARK: - Pre-iOS-26 fallback (VNRecognizeTextRequest)

    private func recognizeLegacy(_ cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(returning: "OCR failed to process: \(error.localizedDescription)")
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(returning: "No text detected in selected image.")
                } else {
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "OCR failed to process: \(error.localizedDescription)")
            }
        }
    }
}
