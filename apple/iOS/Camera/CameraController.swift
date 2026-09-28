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
     diagnose("after start")
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
   center.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
    self?.diagnose("\(note.name.rawValue) \(note.userInfo ?? [:])")
    self?.restart()
   }
  }
  center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
   self?.diagnose("interrupted \(note.userInfo ?? [:])")
  }
 }

 /// Temporary diagnostics for the black-preview issue (printed to the device console in Debug builds).
 private func diagnose(_ event: String) {
  #if DEBUG
  let device = (session.inputs.first as? AVCaptureDeviceInput)?.device
  print("[Camera] \(event) | running=\(session.isRunning) interrupted=\(session.isInterrupted)",
   "device=\(device?.deviceType.rawValue ?? "-") active=\(device?.activeFormat.description ?? "-")",
   "zoom=\(device?.videoZoomFactor ?? 0) min=\(device?.minAvailableVideoZoomFactor ?? 0)",
   "connected=\(device?.isConnected ?? false) suspended=\(device?.isSuspended ?? false)")
  #endif
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
  // The physical ultra-wide camera ("0.5x"): a whole page fits from a low height (owner's request), and on Pro
  // models this lens also does macro, so close shots stay sharp. A physical device is used on purpose: with the
  // triple-camera virtual device at zoom 1.0 the session ran but the preview stayed black (device finding).
  // Fallback: the wide camera.
  let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
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
  // Pages are close: restricting autofocus to near distances makes it faster and less likely to hunt.
  if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
  if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
  if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
  // Refocus when the phone moves to the next page.
  camera.isSubjectAreaChangeMonitoringEnabled = true
 }
}
