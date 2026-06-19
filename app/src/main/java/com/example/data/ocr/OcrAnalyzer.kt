package com.example.data.ocr

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

class OcrAnalyzer {
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    suspend fun analyze(bitmap: Bitmap): String = suspendCancellableCoroutine { continuation ->
        try {
            val image = InputImage.fromBitmap(bitmap, 0)
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val text = visionText.text
                    if (text.isBlank()) {
                        continuation.resume("No text detected in selected image.")
                    } else {
                        continuation.resume(text)
                    }
                }
                .addOnFailureListener { e ->
                    continuation.resume("OCR failed to process: ${e.localizedMessage}")
                }
        } catch (e: Exception) {
            continuation.resume("Bitmap load error: ${e.localizedMessage}")
        }
    }
}
