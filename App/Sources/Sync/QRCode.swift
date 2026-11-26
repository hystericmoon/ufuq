import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCode {
    /// A crisp QR image for `text`, or nil when it cannot be encoded.
    static func image(for text: String, scale: CGFloat = 8) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return Image(decorative: cg, scale: 1).interpolation(.none)
    }
}
