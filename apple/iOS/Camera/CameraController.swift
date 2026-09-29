@preconcurrency import AVFoundation
import Foundation
import os

/// Minimal photo camera on AVFoundation (docs/architecture.md, section 12).
///
/// A custom camera (not UIImagePickerController / VisionKit scanner) because only it allows the required flow:
/// capture -> confirm -> the page is added and uploading starts -> back to the viewfinder immediately.
///
/// Reliability rules (device finding 2026-09-29: black viewfinder "every other time", cured by opening Apple's
/// Camera app):
/// - **One session for the whole app** (`shared`). Previously every camera screen created its own session and
///  stopped the old one asynchronously; two sessions then competed for the same camera and the new one could
///  stay black. Apple's AVCam sample also keeps a single session.
/// - All session work runs on one serial queue, so start / stop / rebuild never overlap.
/// - **Watchdog**: a running session must deliver frames. If none arrive within `frameTimeout`, the session is
///  rebuilt (inputs and outputs removed and added again) - the in-app equivalent of what opening Apple's Camera
///  app did by hand. After `maxRebuilds` failed attempts the screen offers a manual restart.
///
/// `@unchecked Sendable`: mutable state is touched only on `queue` (session) or under `frameLock` (frame time).
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate,
 @unchecked Sendable {

 static let shared = CameraController()

 let session = AVCaptureSession()
 private let photoOutput = AVCapturePhotoOutput()
 /// Frames are only counted (for the watchdog), never processed; late frames are dropped.
 private let frameOutput = AVCaptureVideoDataOutput()
 private let queue = DispatchQueue(label: "aicopilot.camera")
 private let frameQueue = DispatchQueue(label: "aicopilot.camera.frames")
 private let log = Logger(subsystem: "aicopilot", category: "camera")
 private var pendingCapture: CheckedContinuation<Data, Error>?

 private let frameLock = OSAllocatedUnfairLock<Date?>(initialState: nil)
 /// Incremented on every start/stop, so a watchdog scheduled for an older start does nothing.
 private var generation = 0
 private var rebuilds = 0
 private var observing = false

 private static let frameTimeout: TimeInterval = 2
 private static let maxRebuilds = 2

 enum Failure: Error { case notAuthorized, noCamera, captureFailed }

 private override init() {
  super.init()
 }

 /// True when a frame arrived recently: the viewfinder really shows the camera.
 var isDeliveringFrames: Bool {
  frameLock.withLock { last in last.map { Date().timeIntervalSince($0) < 1 } ?? false }
 }

 /// Asks for permission on first use (text from NSCameraUsageDescription), configures the back camera once
 /// and starts it. Idempotent: calling it while running only re-arms the watchdog.
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
     observeSessionEventsOnce()
     rebuilds = 0
     startRunningAndWatch()
     continuation.resume()
    } catch {
     continuation.resume(throwing: error)
    }
   }
  }
 }

 func stop() {
  queue.async { [self] in
   generation += 1
   if session.isRunning { session.stopRunning() }
   frameLock.withLock { $0 = nil }
  }
 }

 /// Manual "Restart camera": a full rebuild, as if the app had never used the camera.
 func rebuild() {
  queue.async { [self] in
   rebuilds = 0
   rebuildOnQueue(reason: "manual")
  }
 }

 // MARK: - Session lifecycle (on `queue`)

 private func startRunningAndWatch() {
  generation += 1
  let startedGeneration = generation
  frameLock.withLock { $0 = nil }
  if !session.isRunning { session.startRunning() }
  queue.asyncAfter(deadline: .now() + Self.frameTimeout) { [self] in
   guard generation == startedGeneration else { return }
   if frameLock.withLock({ $0 }) == nil {
    log.error("No camera frames \(Self.frameTimeout)s after start (running=\(self.session.isRunning), interrupted=\(self.session.isInterrupted))")
    guard rebuilds < Self.maxRebuilds else { return }
    rebuilds += 1
    rebuildOnQueue(reason: "no frames")
   }
  }
 }

 /// Drops the camera input and outputs and adds them again, then starts. This makes AVFoundation reacquire
 /// the camera device from scratch.
 private func rebuildOnQueue(reason: String) {
  log.notice("Rebuilding camera session: \(reason)")
  if session.isRunning { session.stopRunning() }
  session.beginConfiguration()
  session.inputs.forEach(session.removeInput)
  session.outputs.forEach(session.removeOutput)
  session.commitConfiguration()
  do {
   try configureIfNeeded()
   startRunningAndWatch()
  } catch {
   log.error("Camera rebuild failed: \(error.localizedDescription)")
  }
 }

 /// The system may interrupt the session (another app took the camera, a call, the app is opened from Shortcuts
 /// before it is fully active). An interrupted session does not always resume by itself: restart it.
 private func observeSessionEventsOnce() {
  guard !observing else { return }
  observing = true
  let center = NotificationCenter.default
  center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
   guard let self else { return }
   queue.async { self.startRunningAndWatch() }
  }
  center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
   guard let self else { return }
   let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
   log.error("Camera runtime error: \(error?.localizedDescription ?? "unknown")")
   queue.async { self.rebuildOnQueue(reason: "runtime error") }
  }
  center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
   let reason = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
   self?.log.notice("Camera interrupted, reason \(reason)")
  }
 }

 private func configureIfNeeded() throws {
  guard session.inputs.isEmpty else { return }
  // The physical ultra-wide camera ("0.5x"): a whole page fits from a low height (owner's request), and on Pro
  // models this lens also does macro, so close shots stay sharp. Fallback: the wide camera.
  let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
   ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  guard let camera else { throw Failure.noCamera }
  session.beginConfiguration()
  defer { session.commitConfiguration() }
  session.sessionPreset = .photo
  let input = try AVCaptureDeviceInput(device: camera)
  if session.canAddInput(input) { session.addInput(input) }
  if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
  photoOutput.maxPhotoQualityPrioritization = .balanced
  frameOutput.alwaysDiscardsLateVideoFrames = true
  frameOutput.setSampleBufferDelegate(self, queue: frameQueue)
  if session.canAddOutput(frameOutput) { session.addOutput(frameOutput) }
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

 // MARK: - Frames (watchdog only)

 func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
  frameLock.withLock { $0 = Date() }
 }

 // MARK: - Photo

 /// Takes one photo and returns its encoded data (HEIC/JPEG as chosen by the system).
 func capture() async throws -> Data {
  try await withCheckedThrowingContinuation { continuation in
   queue.async { [self] in
    guard session.isRunning, pendingCapture == nil else {
     continuation.resume(throwing: Failure.captureFailed)
     return
    }
    pendingCapture = continuation
    let settings = AVCapturePhotoSettings()
    // Pages: prefer sharpness over speed-optimized processing, but keep it fast enough for repeated shots.
    settings.photoQualityPrioritization = .balanced
    photoOutput.capturePhoto(with: settings, delegate: self)
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
}
