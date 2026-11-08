import Flutter
import Photos

/// `io.jeph.grlab/media`: saves one shot as one Photos asset. A RAW+JPEG
/// pair becomes a JPEG photo with the DNG as its RAW alternate, a lone DNG
/// a RAW photo, a MOV a video.
///
/// Only add-only access is requested: it never exposes the user's library,
/// but it cannot create or find albums, so the album argument is unused.
final class MediaPlugin: NSObject, FlutterPlugin {
  private struct ShotFile {
    let url: URL
    let name: String
    let kind: String
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.jeph.grlab/media", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(MediaPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "saveShot" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    let files = (args?["files"] as? [[String: Any]])?.compactMap { file -> ShotFile? in
      guard let path = file["path"] as? String,
        let name = file["name"] as? String,
        let kind = file["kind"] as? String
      else { return nil }
      return ShotFile(url: URL(fileURLWithPath: path), name: name, kind: kind)
    }
    guard let files, !files.isEmpty, files.count == (args?["files"] as? [Any])?.count else {
      result(FlutterError(
        code: "failed", message: "saveShot needs files with path, name and kind", details: nil))
      return
    }
    let reply: (FlutterError?) -> Void = { error in
      DispatchQueue.main.async { result(error) }
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        reply(FlutterError(
          code: "permissionDenied",
          message: "GR Lab may not add to Photos; allow it under Settings › GR Lab › Photos",
          details: nil))
        return
      }
      Self.save(files, reply: reply)
    }
  }

  private static func save(_ files: [ShotFile], reply: @escaping (FlutterError?) -> Void) {
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      for (index, file) in files.enumerated() {
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = file.name
        options.uniformTypeIdentifier = uniformType(file.kind)
        request.addResource(with: resourceType(file.kind, index: index), fileURL: file.url, options: options)
      }
    }) { success, error in
      if success {
        reply(nil)
        return
      }
      reply(Self.saveError(error))
    }
  }

  /// The Dart side sends the JPEG before the DNG, so a DNG after the first
  /// file is the RAW half of a pair.
  private static func resourceType(_ kind: String, index: Int) -> PHAssetResourceType {
    switch kind {
    case "movie": return .video
    case "dng" where index > 0: return .alternatePhoto
    default: return .photo
    }
  }

  private static func uniformType(_ kind: String) -> String {
    switch kind {
    case "movie": return "com.apple.quicktime-movie"
    case "dng": return "com.adobe.raw-image"
    default: return "public.jpeg"
    }
  }

  private static func saveError(_ error: Error?) -> FlutterError {
    if let error = error as NSError?, error.domain == PHPhotosErrorDomain,
      error.code == PHPhotosError.Code.accessUserDenied.rawValue
        || error.code == PHPhotosError.Code.accessRestricted.rawValue
    {
      return FlutterError(
        code: "permissionDenied", message: "GR Lab may not add to Photos", details: nil)
    }
    return FlutterError(
      code: "failed",
      message: "saving to Photos failed: \(error?.localizedDescription ?? "unknown error")",
      details: nil)
  }
}
