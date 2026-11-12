import Foundation

/// Where the native code keeps what has to outlive the Flutter engine and
/// the process: the recorded location history and the flags that say what to
/// start again at launch.
///
/// It is a directory of its own under Application Support, kept out of
/// iCloud and computer backups like the rest of GR Photo's data. That is
/// also why the flags are not in `UserDefaults`, which is backed up: restored
/// on another phone they would start the location history there at first
/// launch, before its user turned it on.
enum NativeStorage {
  /// The directory, created on first use.
  static func directory() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var directory = support.appendingPathComponent("gr-camera-native", isDirectory: true)
    guard !FileManager.default.fileExists(atPath: directory.path) else { return directory }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    return directory
  }

  /// Options for every file written here: replaced in one step, and readable
  /// with the phone locked (a background launch has to read and write them)
  /// once it was unlocked after a restart.
  static let writingOptions: Data.WritingOptions = [
    .atomic, .completeFileProtectionUntilFirstUserAuthentication,
  ]
}

/// A few values kept across launches as a property list in [NativeStorage].
/// Main queue only.
final class StateFile {
  private let name: String
  private var values: [String: Any] = [:]

  /// False while the file exists and cannot be read, which is the case
  /// between a restart of the phone and its first unlock. The values then
  /// read as unset, and nothing is written over the file.
  private var readable = true

  init(name: String) {
    self.name = name
    reload()
  }

  /// Reads the file again; the values in memory stay when it cannot be read.
  func reload() {
    guard let url = try? NativeStorage.directory().appendingPathComponent("\(name).plist")
    else {
      readable = false
      return
    }
    guard let data = try? Data(contentsOf: url) else {
      readable = !FileManager.default.fileExists(atPath: url.path)
      return
    }
    readable = true
    let list = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    values = list as? [String: Any] ?? [:]
  }

  func bool(_ key: String) -> Bool {
    values[key] as? Bool ?? false
  }

  func int64(_ key: String) -> Int64? {
    (values[key] as? NSNumber)?.int64Value
  }

  /// Sets `key` (nil removes it) and writes the file. The value is kept in
  /// memory when the write fails.
  func set(_ value: Any?, for key: String) throws {
    if !readable { reload() }
    values[key] = value
    guard readable else {
      throw CocoaError(.fileReadNoPermission)
    }
    let url = try NativeStorage.directory().appendingPathComponent("\(name).plist")
    let data = try PropertyListSerialization.data(
      fromPropertyList: values, format: .binary, options: 0)
    try data.write(to: url, options: NativeStorage.writingOptions)
  }
}
