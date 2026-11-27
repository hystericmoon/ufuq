import CoreImage
import Foundation
import ImageIO
import UfuqCore
import UniformTypeIdentifiers
@preconcurrency import Vision

enum VisionTransformError: Error, LocalizedError {
    case unreadableImage
    case noForegroundSubject
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "Could not read image"
        case .noForegroundSubject: return "No foreground subject found"
        case .encodeFailed: return "Could not write PNG output"
        }
    }
}

/// On-device Vision transforms: OCR text recognition and foreground mask background removal.
enum VisionServices {
    static func recognizeText(at imageURL: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(url: imageURL)
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    static func removeBackground(at imageURL: URL) async throws -> URL {
        let outputPath = TrayActions().removeBackgroundOutput(imageURL.path)
        let outputURL = URL(fileURLWithPath: outputPath)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(url: imageURL)
            try handler.perform([request])

            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw VisionTransformError.noForegroundSubject
            }
            let maskedBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            let context = CIContext(options: nil)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent),
                  let destination = CGImageDestinationCreateWithURL(
                      outputURL as CFURL,
                      UTType.png.identifier as CFString,
                      1,
                      nil
                  ) else {
                throw VisionTransformError.encodeFailed
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw VisionTransformError.encodeFailed
            }
            return outputURL
        }.value
    }

    /// Launches interactive region screenshot via `/usr/sbin/screencapture -i -x`, runs OCR, and returns recognized lines.
    /// Returns `nil` if the user cancels the selection.
    static func captureScreenAndOCR() async -> Result<[String], Error>? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ufuq-ocr-\(UUID().uuidString).png")

        let captured = await Task.detached(priority: .userInitiated) { () -> Bool in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", tempURL.path]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: tempURL.path)
            } catch {
                return false
            }
        }.value

        guard captured else { return nil }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let lines = try await recognizeText(at: tempURL)
            return .success(lines)
        } catch {
            return .failure(error)
        }
    }
}
