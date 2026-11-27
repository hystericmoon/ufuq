import AppKit
import AVFoundation
import PDFKit
import XCTest
import UfuqCore
@testable import Ufuq

final class Phase8MacTests: XCTestCase {
    private let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ufuq-phase8-tests-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCombineToPDFMergesImagesIntoMultiPagePDF() throws {
        let img1 = try writeTextPNG(text: "Page One", name: "p1.png", size: CGSize(width: 240, height: 120))
        let img2 = try writeTextPNG(text: "Page Two", name: "p2.png", size: CGSize(width: 240, height: 120))

        let output = try MediaTransformer.combineToPDF(urls: [img1, img2])
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let pdf = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(pdf.pageCount, 2)
    }

    func testCompressVideoProducesPlayableMP4() async throws {
        let inputURL = try await writeSampleVideo(name: "clip.mov")
        let compressed = try await MediaTransformer.compressVideo(at: inputURL)
        XCTAssertEqual(compressed.pathExtension.lowercased(), "mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: compressed.path))
        let tracks = try await AVURLAsset(url: compressed).loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty)
    }

    func testVisionOCRRecognizesRenderedText() async throws {
        let img = try writeTextPNG(text: "UFUQ PHASE EIGHT", name: "ocr.png", size: CGSize(width: 480, height: 140))
        let lines = try await VisionServices.recognizeText(at: img)
        let joined = lines.joined(separator: " ").uppercased()
        XCTAssertTrue(joined.contains("UFUQ") || joined.contains("PHASE"), "Got OCR lines: \(lines)")
    }

    func testVisionRemoveBackgroundThrowsCleanlyOnBlankImage() async throws {
        let blank = try writeSolidPNG(name: "blank.png", color: .white, size: CGSize(width: 120, height: 120))
        do {
            let output = try await VisionServices.removeBackground(at: blank)
            // Some Vision engines may fail or produce a file; either way it must never crash.
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testMeetingsTileAppearsForMeetingOrActiveDevices() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = BentoContent(now: now)
        XCTAssertFalse(empty.showsMeetings)
        XCTAssertFalse(empty.smallTiles.contains(.meetings))

        let withMic = BentoContent(now: now, mediaDevices: MediaDeviceSnapshot(isMicInUse: true))
        XCTAssertTrue(withMic.showsMeetings)
        XCTAssertTrue(withMic.smallTiles.contains(.meetings))

        let event = MeetingEvent(
            id: "1",
            title: "Sync",
            startDate: now.addingTimeInterval(180),
            endDate: now.addingTimeInterval(1800),
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        let withMeeting = BentoContent(now: now, meeting: event)
        XCTAssertTrue(withMeeting.showsMeetings)
        XCTAssertEqual(MeetingsTileFormat.timingBadge(for: event, at: now), "in 3m")
    }

    // MARK: - Helpers

    private func writeTextPNG(text: String, name: String, size: CGSize) throws -> URL {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(at: NSPoint(x: 24, y: size.height / 2 - 20), withAttributes: attrs)
        image.unlockFocus()
        return try savePNG(image: image, name: name)
    }

    private func writeSolidPNG(name: String, color: NSColor, size: CGSize) throws -> URL {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return try savePNG(image: image, name: name)
    }

    private func savePNG(image: NSImage, name: String) throws -> URL {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = tempDir.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    private func writeSampleVideo(name: String) async throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        if let pool = adaptor.pixelBufferPool {
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            if let pb {
                adaptor.append(pb, withPresentationTime: .zero)
                adaptor.append(pb, withPresentationTime: CMTime(seconds: 0.1, preferredTimescale: 600))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
