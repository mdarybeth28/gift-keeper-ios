import SwiftUI
import UIKit

/// Photo plumbing for the gift blob: the web stores gift photos
/// as data URLs inside the blob ("data:image/jpeg;base64,…"), and
/// the readers/feedback chain pass prepped JPEGs (the web's
/// feedbackPrepPhoto: 1600px long edge, JPEG 0.85, trouble means
/// send the original). These helpers are the native twins.
enum GiftPhoto {
    /// A UIImage out of a blob data URL (or a bare base64 string).
    static func image(fromDataURL text: String?) -> UIImage? {
        guard let text, !text.isEmpty else { return nil }
        let payload: String
        if let comma = text.firstIndex(of: ",") {
            payload = String(text[text.index(after: comma)...])
        } else {
            payload = text
        }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UIImage(data: data)
    }

    /// A data URL for storing in the blob, from prepped JPEG data.
    static func dataURL(fromJPEG data: Data) -> String {
        "data:image/jpeg;base64," + data.base64EncodedString()
    }

    /// Downscale to reader size, the web's feedbackPrepPhoto twin:
    /// long edge capped at 1600, JPEG 0.85. Any trouble and the
    /// original data is what goes — prep can never block a send.
    static func preparedJPEG(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxEdge: CGFloat = 1600
        let longEdge = max(image.size.width, image.size.height)
        var drawImage = image
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            drawImage = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
        return drawImage.jpegData(compressionQuality: 0.85) ?? data
    }
}

/// A gift photo stored in the blob, shown at a fixed thumbnail
/// size (the web's gift rows show the photo the same way).
struct GiftPhotoView: View {
    let dataURL: String?
    var size: CGFloat = 52

    var body: some View {
        if let image = GiftPhoto.image(fromDataURL: dataURL) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
