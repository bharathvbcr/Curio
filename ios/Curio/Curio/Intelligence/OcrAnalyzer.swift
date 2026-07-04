import Foundation
import Vision
import UIKit

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

    /// Recognizes text in `image`, returning the joined recognized strings or one of the fallback
    /// strings above. Never throws. Plain `suspend` → `async` (no throws), per CONVENTIONS §3.
    func analyze(_ image: UIImage) async -> String {
        // Mirror the Kotlin `try { InputImage.fromBitmap(...) } catch → "Bitmap load error: …"`:
        // a missing CGImage means the bitmap could not be loaded into the recognizer.
        guard let cgImage = image.cgImage else {
            return "Bitmap load error: no underlying image data"
        }

        if #available(iOS 26, *) {
            return await recognizeModern(cgImage)
        } else {
            return await recognizeLegacy(cgImage)
        }
    }

    // MARK: - iOS 26+ async RecognizeTextRequest

    @available(iOS 26, *)
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
