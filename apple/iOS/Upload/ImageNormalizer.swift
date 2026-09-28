import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image ready for upload: a JPEG file on disk plus the facts the backend verifies.
struct PreparedImage: Sendable {
 let fileURL: URL
 let byteSize: Int64
 /// Lower-case hex SHA-256 of the file (the backend rejects an upload that does not match).
 let sha256: String
 let width: Int
 let height: Int
}

/// Turns a camera / library photo (HEIC or JPEG, up to 24 MP) into a small upload-ready JPEG.
///
/// Parameters come from the benchmark on real exam pages (docs/phase-3-image-benchmark.md):
/// 1536 px long edge + JPEG 0.8 = ~0.5 MB per page, 7/7 correct answers, half the upload of 2048 px.
///
/// Swift notes: an `enum` without cases is a namespace for static functions (like a Java utility class
/// with a private constructor). Everything here is pure and thread-safe, so it runs off the main thread.
enum ImageNormalizer {
 static let maxLongEdge = 1536
 static let jpegQuality = 0.8

 /// Folder for files waiting to be uploaded. Application Support survives app restarts
 /// (a background upload may finish while the app is not running) and is not visible to the user.
 static let uploadsDirectory: URL = {
  let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  let directory = base.appending(path: "PendingUploads", directoryHint: .isDirectory)
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
 }()

 static func fileURL(for id: UUID) -> URL {
  uploadsDirectory.appending(path: "\(id.uuidString).jpg")
 }

 enum Failure: Error { case unreadableImage, encodingFailed }

 /// Resizes, applies the EXIF orientation, encodes as JPEG, writes the file and hashes it.
 static func prepare(_ data: Data, id: UUID) throws -> PreparedImage {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadableImage }
  // ImageIO's thumbnail API decodes at the target size directly (fast, low memory) and applies orientation.
  let options: [CFString: Any] = [
   kCGImageSourceCreateThumbnailFromImageAlways: true,
   kCGImageSourceCreateThumbnailWithTransform: true,
   kCGImageSourceThumbnailMaxPixelSize: maxLongEdge,
  ]
  guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
   throw Failure.unreadableImage
  }

  let output = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
   throw Failure.encodingFailed
  }
  CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
  guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }

  let jpeg = output as Data
  let url = fileURL(for: id)
  try jpeg.write(to: url, options: .atomic)
  let digest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
  return PreparedImage(fileURL: url, byteSize: Int64(jpeg.count), sha256: digest, width: image.width, height: image.height)
 }

 /// Small preview for the draft screen, read from the prepared file.
 static func thumbnail(of url: URL, maxPixelSize: Int = 300) -> CGImage? {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  let options: [CFString: Any] = [
   kCGImageSourceCreateThumbnailFromImageAlways: true,
   kCGImageSourceCreateThumbnailWithTransform: true,
   kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
  ]
  return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
 }
}
