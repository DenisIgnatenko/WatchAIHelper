import AVFoundation
import SwiftUI
import UIKit

/// Full-screen camera for photographing pages (spec 18, 20):
/// shutter -> preview [Retake] [Use] -> Use adds the page, starts its upload and returns to the viewfinder.
/// "Done" closes the camera; confirming never triggers AI inference (Invariant 2).
struct CameraView: View {
 @Environment(DraftStore.self) private var store
 @Environment(\.dismiss) private var dismiss
 @State private var camera = CameraController()
 /// The photo waiting for the user's confirmation.
 @State private var captured: Data?
 @State private var capturing = false
 @State private var errorText: String?
 /// Pages confirmed in this camera session (counter on the Done button).
 @State private var confirmedCount = 0

 var body: some View {
  ZStack {
   Color.black.ignoresSafeArea()
   if let captured, let image = UIImage(data: captured) {
    Image(uiImage: image).resizable().scaledToFit()
   } else {
    CameraPreview(session: camera.session).ignoresSafeArea()
   }
   VStack {
    Spacer()
    if let errorText {
     Text(errorText).foregroundStyle(.white).padding(8).background(.red.opacity(0.8), in: .capsule)
    }
    controls.padding(.bottom, 24)
   }
  }
  .task {
   do {
    try await camera.start()
   } catch {
    errorText = "Camera unavailable. Allow camera access in Settings."
   }
  }
  .onDisappear { camera.stop() }
  .statusBarHidden()
 }

 @ViewBuilder
 private var controls: some View {
  if captured != nil {
   HStack(spacing: 40) {
    Button("Retake") { captured = nil }
     .buttonStyle(.bordered).tint(.white)
    Button {
     confirm()
    } label: {
     Label("Use", systemImage: "checkmark").font(.title3.bold()).padding(.horizontal, 12)
    }
    .buttonStyle(.borderedProminent)
   }
  } else {
   HStack {
    Button("Done") { dismiss() }
     .buttonStyle(.bordered).tint(.white)
     .frame(width: 100)
    Spacer()
    Button(action: shoot) {
     Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
      .overlay(Circle().fill(.white).padding(8))
    }
    .disabled(capturing)
    Spacer()
    VStack(spacing: 4) {
     Text("0.5×").font(.caption.bold()).foregroundStyle(.yellow)
     Text(confirmedCount == 0 ? "" : "\(confirmedCount) page\(confirmedCount == 1 ? "" : "s")")
      .foregroundStyle(.white)
    }
    .frame(width: 100)
   }
   .padding(.horizontal, 20)
  }
 }

 private func shoot() {
  capturing = true
  Task {
   defer { capturing = false }
   do {
    captured = try await camera.capture()
   } catch {
    errorText = "Capture failed. Try again."
   }
  }
 }

 /// Adds the page to the draft (upload starts in the background) and returns to the viewfinder at once.
 private func confirm() {
  guard let data = captured else { return }
  store.addPhoto(data, source: .camera)
  confirmedCount += 1
  captured = nil
 }
}

/// Live camera preview: a UIKit layer wrapped for SwiftUI.
/// `UIViewRepresentable` is SwiftUI's bridge to UIKit views (like embedding a Swing component in JavaFX).
private struct CameraPreview: UIViewRepresentable {
 let session: AVCaptureSession

 func makeUIView(context: Context) -> PreviewView {
  let view = PreviewView()
  view.previewLayer.session = session
  view.previewLayer.videoGravity = .resizeAspectFill
  return view
 }

 func updateUIView(_ uiView: PreviewView, context: Context) {}

 final class PreviewView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
 }
}
