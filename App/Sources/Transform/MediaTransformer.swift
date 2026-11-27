import AppKit
@preconcurrency import AVFoundation
import Foundation
import PDFKit
import UfuqCore

enum MediaTransformError: Error, LocalizedError {
    case unsupportedVideo
    case exportFailed(String)
    case noPDFInputs
    case pdfWriteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVideo: return "Cannot compress this video format"
        case .exportFailed(let reason): return reason
        case .noPDFInputs: return "No images or PDFs to combine"
        case .pdfWriteFailed: return "Could not write the PDF"
        }
    }
}

/// On-device media transformations: video compression (AVFoundation) and combine-to-PDF (PDFKit).
enum MediaTransformer {
    static func compressVideo(at inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let preferred = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetHighestQuality,
        ]
        var chosenPreset: String?
        for candidate in preferred {
            if await AVAssetExportSession.compatibility(
                ofExportPreset: candidate,
                with: asset,
                outputFileType: AVFileType.mp4
            ) {
                chosenPreset = candidate
                break
            }
        }
        guard let preset = chosenPreset,
              let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw MediaTransformError.unsupportedVideo
        }

        let outputPath = TrayActions().compressVideoOutput(inputURL.path)
        let outputURL = URL(fileURLWithPath: outputPath)
        session.shouldOptimizeForNetworkUse = true

        if #available(macOS 15.0, *) {
            try await session.export(to: outputURL, as: AVFileType.mp4)
            return outputURL
        } else {
            session.outputURL = outputURL
            session.outputFileType = AVFileType.mp4
            await withCheckedContinuation { continuation in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
            if session.status == AVAssetExportSession.Status.completed {
                return outputURL
            }
            throw MediaTransformError.exportFailed(session.error?.localizedDescription ?? "Video export failed")
        }
    }

    static func combineToPDF(urls: [URL]) throws -> URL {
        let document = PDFDocument()
        var firstDirectory: String?

        for url in urls {
            let ext = url.pathExtension
            if TrayActions.isPDFExtension(ext) {
                guard let sourcePDF = PDFDocument(url: url) else { continue }
                if firstDirectory == nil { firstDirectory = url.deletingLastPathComponent().path }
                for pageIndex in 0..<sourcePDF.pageCount {
                    if let page = sourcePDF.page(at: pageIndex) {
                        document.insert(page, at: document.pageCount)
                    }
                }
            } else if TrayActions.isImageExtension(ext),
                      let image = NSImage(contentsOf: url),
                      let page = PDFPage(image: image) {
                if firstDirectory == nil { firstDirectory = url.deletingLastPathComponent().path }
                document.insert(page, at: document.pageCount)
            }
        }

        guard document.pageCount > 0, let directory = firstDirectory else {
            throw MediaTransformError.noPDFInputs
        }
        let stem = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Combined"
        let outputPath = TrayActions().combinePDFOutput(directory: directory, stem: stem)
        let outputURL = URL(fileURLWithPath: outputPath)
        guard document.write(to: outputURL) else {
            throw MediaTransformError.pdfWriteFailed
        }
        return outputURL
    }
}
