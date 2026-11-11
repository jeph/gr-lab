import Flutter
import Photos

/// `io.jeph.grlab/media`: saves one shot as one Photos asset in the album
/// the Dart side names, which is created when the library has none of that
/// title. A RAW+JPEG pair becomes a JPEG photo with the DNG as its RAW
/// alternate, a lone DNG a RAW photo, a MOV a video.
///
/// Photos lets only an app with full access create or look up albums, so
/// full access is what is asked for. The plugin uses it to find the album by
/// its title and reads nothing else. With limited access or "Add Photos
/// Only" the shot is still saved, outside the album.
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
    let album = args?["album"] as? String
    let files = (args?["files"] as? [[String: Any]])?.compactMap { file -> ShotFile? in
      guard let path = file["path"] as? String,
        let name = file["name"] as? String,
        let kind = file["kind"] as? String
      else { return nil }
      return ShotFile(url: URL(fileURLWithPath: path), name: name, kind: kind)
    }
    guard let album, let files, !files.isEmpty, files.count == (args?["files"] as? [Any])?.count
    else {
      result(FlutterError(
        code: "failed", message: "saveShot needs an album and files with path, name and kind",
        details: nil))
      return
    }
    let reply: (FlutterError?) -> Void = { error in
      DispatchQueue.main.async { result(error) }
    }
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
      if status == .authorized {
        Self.save(files, album: album, reply: reply)
        return
      }
      // Refusing access to the library leaves "Add Photos Only" in place
      // when the user chose that in Settings.
      let mayAdd =
        status == .limited || PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
      guard mayAdd else {
        reply(FlutterError(
          code: "permissionDenied",
          message: "GR Lab may not add to Photos; allow it under Settings › GR Lab › Photos",
          details: nil))
        return
      }
      Self.save(files, album: nil, reply: reply)
    }
  }

  /// Saves the shot and, given an `album`, adds it to the album of that
  /// title in the same change, so the shot never lands without its album.
  private static func save(
    _ files: [ShotFile], album: String?, reply: @escaping (FlutterError?) -> Void
  ) {
    let existingAlbum = album.flatMap(findAlbum(titled:))
    PHPhotoLibrary.shared().performChanges({
      let request = PHAssetCreationRequest.forAsset()
      for (index, file) in files.enumerated() {
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = file.name
        options.uniformTypeIdentifier = uniformType(file.kind)
        request.addResource(with: resourceType(file.kind, index: index), fileURL: file.url, options: options)
      }
      guard let album, let asset = request.placeholderForCreatedAsset else { return }
      let albumRequest =
        existingAlbum.flatMap { PHAssetCollectionChangeRequest(for: $0) }
        ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: album)
      albumRequest.addAssets([asset] as NSArray)
    }) { success, error in
      if success {
        reply(nil)
        return
      }
      reply(Self.saveError(error))
    }
  }

  /// The user's album of this title, if the library has one. A renamed or
  /// deleted album is not found, and the next save creates it again.
  private static func findAlbum(titled title: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title = %@", title)
    options.fetchLimit = 1
    return PHAssetCollection.fetchAssetCollections(
      with: .album, subtype: .albumRegular, options: options
    ).firstObject
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
