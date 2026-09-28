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
     observeInterruptionsOnce()
     if !session.isRunning { session.startRunning() }
     continuation.resume()
    } catch {
     continuation.resume(throwing: error)
    }
   }
  }
 }

 private var observing = false

 /// The system may interrupt or fail the session - e.g. when the app is opened from Shortcuts via
 /// aicopilot://camera and is not fully in the foreground yet. A session started in that moment does not
 /// resume by itself, which left the preview black. Restart it when the interruption ends or after an error.
 private func observeInterruptionsOnce() {
  guard !observing else { return }
  observing = true
  let center = NotificationCenter.default
  for name in [AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
   center.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
    self?.restart()
   }
  }
 }

 /// Starts the session again if it is not running (idempotent). Also called when the app becomes active.
 func restart() {
  queue.async { [session] in
   if !session.isRunning { session.startRunning() }
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
  // The triple-camera virtual device: at its minimum zoom factor it uses the ultra-wide lens ("0.5x"),
  // so a whole page fits from a low height (owner's request), and it switches to macro automatically
  // when the phone is close to the paper. Fallback: the plain wide camera.
  let camera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
   ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  guard let camera else { throw Failure.noCamera }
  session.beginConfiguration()
  defer { session.commitConfiguration() }
  session.sessionPreset = .photo
  let input = try AVCaptureDeviceInput(device: camera)
  if session.canAddInput(input) { session.addInput(input) }
  if session.canAddOutput(output) { session.addOutput(output) }
  output.maxPhotoQualityPrioritization = .balanced
  try configureForDocuments(camera)
 }

 /// Settings that help text recognition of paper pages.
 private func configureForDocuments(_ camera: AVCaptureDevice) throws {
  try camera.lockForConfiguration()
  defer { camera.unlockForConfiguration() }
  // Widest field of view = ultra-wide lens on the triple camera (zoom 1.0 is shown as "0.5x" in Apple's Camera).
  camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
  // Pages are close: restricting autofocus to near distances makes it faster and less likely to hunt.
  if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
  if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
  if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
  // Refocus when the phone moves to the next page.
  camera.isSubjectAreaChangeMonitoringEnabled = true
 }
}
