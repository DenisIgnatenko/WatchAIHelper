import SwiftUI
import UIKit
import VisionKit

/// Page capture with Apple's document scanner (VisionKit, the scanner of Notes and Files).
///
/// Why the system scanner instead of our own AVFoundation camera (decision 2026-09-29):
/// - Reliability. With our own capture session the camera hung system-wide (black viewfinder also in Apple's
///  Camera app, fixed only by a reboot), and it kept happening after every change we tried. The scanner is
///  configured and driven by iOS itself; the app never touches the camera hardware (docs PI 4.4).
/// - Better pages. It finds the sheet, corrects the perspective of a photo taken at an angle and crops the
///  background, so the whole 1536 px budget goes to the text.
///
/// Flow: scan pages one after another (auto-capture when the sheet is steady, or the shutter) -> Save ->
/// all pages go into the draft in scan order and upload in the background. Saving never starts AI inference
/// (Invariant 2); only Send does.
struct DocumentScannerView: UIViewControllerRepresentable {
 @Environment(DraftStore.self) private var store
 @Environment(\.dismiss) private var dismiss

 /// False on devices without a camera (simulator): the caller shows a message instead.
 static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

 func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
  let scanner = VNDocumentCameraViewController()
  scanner.delegate = context.coordinator
  return scanner
 }

 func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

 func makeCoordinator() -> Coordinator {
  Coordinator(onPages: { pages in
   // Same path as library photos: normalized, registered in this order, uploaded in the background.
   for page in pages { store.addPhoto(page, source: .camera) }
  }, onClose: { dismiss() })
 }

 /// UIKit delegate -> SwiftUI closures. `@MainActor`: VisionKit calls its delegate on the main thread.
 @MainActor
 final class Coordinator: NSObject, @MainActor VNDocumentCameraViewControllerDelegate {
  private let onPages: ([Data]) -> Void
  private let onClose: () -> Void

  init(onPages: @escaping ([Data]) -> Void, onClose: @escaping () -> Void) {
   self.onPages = onPages
   self.onClose = onClose
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
   // JPEG 0.9 here; ImageNormalizer then resizes to the upload size (1536 px, JPEG 0.8).
   let pages = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9) }
   onPages(pages)
   onClose()
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
   onClose()
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
   onClose()
  }
 }
}
