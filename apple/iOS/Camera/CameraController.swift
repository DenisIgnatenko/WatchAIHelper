@preconcurrency import AVFoundation
import Foundation

/// Minimal photo camera on AVFoundation (docs/architecture.md, section 12).
///
/// A custom camera (not UIImagePickerController / VisionKit scanner) because only it allows the required flow:
/// capture -> confirm -> the page is added and uploading starts -> back to the viewfinder immediately.
///
/// Threading: AVCaptureSession must be configured and started off the main thread, so all session work
/// runs on a private serial queue. `@unchecked Sendable`: the session is only touched on that queue.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

 let session = AVCaptureSession()
 private let output = AVCapturePhotoOutput()
 private let queue = DispatchQueue(label: "aicopilot.camera")
 private var pendingCapture: CheckedContinuation<Data, Error>?

 enum Failure: Error { case notAuthorized, noCamera, captureFailed }

 /// Asks for permission on first use (text from NSCameraUsageDescription), then configures the back camera.
 func start() async throws {
  switch AVCaptureDevice.authorizationStatus(for: .video) {
  case .authorized: break
  case .notDetermined:
   guard await AVCaptureDevice.requestAccess(for: .video) else { throw Failure.notAuthorized }
  default: throw Failure.notAuthorized
  }
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
   queue.async { [self] in
    do {
     try configureIfNeeded()
     if !session.isRunning { session.startRunning() }
     continuation.resume()
    } catch {
     continuation.resume(throwing: error)
    }
   }
  }
 }

 func stop() {
  queue.async { [session] in
   if session.isRunning { session.stopRunning() }
  }
 }

 /// Takes one photo and returns its encoded data (HEIC/JPEG as chosen by the system).
 func capture() async throws -> Data {
  try await withCheckedThrowingContinuation { continuation in
   queue.async { [self] in
    pendingCapture = continuation
    let settings = AVCapturePhotoSettings()
    // Pages: prefer sharpness over speed-optimized processing, but keep it fast enough for repeated shots.
    settings.photoQualityPrioritization = .balanced
    output.capturePhoto(with: settings, delegate: self)
   }
  }
 }

 func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
  queue.async { [self] in
   let continuation = pendingCapture
   pendingCapture = nil
   if let data = photo.fileDataRepresentation(), error == nil {
    continuation?.resume(returning: data)
   } else {
    continuation?.resume(throwing: error ?? Failure.captureFailed)
   }
  }
 }

 private func configureIfNeeded() throws {
  guard session.inputs.isEmpty else { return }
  guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
   throw Failure.noCamera
  }
  session.beginConfiguration()
  defer { session.commitConfiguration() }
  session.sessionPreset = .photo
  let input = try AVCaptureDeviceInput(device: camera)
  if session.canAddInput(input) { session.addInput(input) }
  if session.canAddOutput(output) { session.addOutput(output) }
  output.maxPhotoQualityPrioritization = .balanced
 }
}
