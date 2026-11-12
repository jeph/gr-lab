import CoreLocation
import Foundation

/// One position of the phone, as the location channel's fix map carries it.
struct LocationFix {
  let latitude: Double
  let longitude: Double

  /// Radius in metres; nil when iOS gave none.
  let accuracy: Double?

  /// Metres above mean sea level; nil when iOS gave none.
  let altitude: Double?

  /// Milliseconds since the epoch, UTC.
  let timeMs: Int64

  init(latitude: Double, longitude: Double, accuracy: Double?, altitude: Double?, timeMs: Int64) {
    self.latitude = latitude
    self.longitude = longitude
    self.accuracy = accuracy
    self.altitude = altitude
    self.timeMs = timeMs
  }

  /// Nil for a location iOS marks as invalid (a negative horizontal
  /// accuracy). A negative vertical accuracy means there is no altitude.
  init?(_ location: CLLocation) {
    guard location.horizontalAccuracy >= 0, CLLocationCoordinate2DIsValid(location.coordinate)
    else { return nil }
    self.init(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      accuracy: location.horizontalAccuracy,
      altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
      timeMs: Self.milliseconds(location.timestamp))
  }

  static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  /// `lat`, `lon`, `t`, and `acc` and `alt` when known.
  var map: [String: Any] {
    var map: [String: Any] = ["lat": latitude, "lon": longitude, "t": timeMs]
    if let accuracy { map["acc"] = accuracy }
    if let altitude { map["alt"] = altitude }
    return map
  }
}

/// The positions recorded for the location history until Dart takes them: a
/// file in [NativeStorage], so recording works with no Flutter engine.
///
/// Each position is 40 bytes, little-endian: the time (int64 milliseconds),
/// then latitude, longitude, accuracy and altitude as doubles, NaN for an
/// accuracy or altitude iOS did not give. Main queue only.
final class LocationHistoryStore {
  /// Older positions are dropped whenever one is appended.
  static let keep: TimeInterval = 90 * 24 * 60 * 60

  /// The most positions kept; the oldest go first.
  static let limit = 20000

  private static let recordSize = 40

  /// Adds `fixes`, dropping every position older than [keep] before `now`
  /// and the oldest ones over [limit].
  func append(_ fixes: [LocationFix], now: Date) throws {
    let oldest = LocationFix.milliseconds(now.addingTimeInterval(-Self.keep))
    let added = fixes.filter { $0.timeMs >= oldest }
    guard !added.isEmpty else { return }
    let url = try fileURL()
    var kept = try read(url).filter { $0.timeMs >= oldest }
    kept.append(contentsOf: added)
    if kept.count > Self.limit {
      kept.sort { $0.timeMs < $1.timeMs }
      kept.removeFirst(kept.count - Self.limit)
    }
    try Self.encode(kept).write(to: url, options: NativeStorage.writingOptions)
  }

  /// Hands over every stored position, oldest first, and empties the store.
  func take() throws -> [LocationFix] {
    let url = try fileURL()
    let fixes = try read(url)
    guard !fixes.isEmpty else { return [] }
    try FileManager.default.removeItem(at: url)
    return fixes.sorted { $0.timeMs < $1.timeMs }
  }

  private func fileURL() throws -> URL {
    try NativeStorage.directory().appendingPathComponent("location-history.bin")
  }

  private func read(_ url: URL) throws -> [LocationFix] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return Self.decode(try Data(contentsOf: url))
  }

  private static func encode(_ fixes: [LocationFix]) -> Data {
    var data = Data(capacity: fixes.count * recordSize)
    func put(_ bits: UInt64) {
      withUnsafeBytes(of: bits.littleEndian) { data.append(contentsOf: $0) }
    }
    for fix in fixes {
      put(UInt64(bitPattern: fix.timeMs))
      put(fix.latitude.bitPattern)
      put(fix.longitude.bitPattern)
      put((fix.accuracy ?? .nan).bitPattern)
      put((fix.altitude ?? .nan).bitPattern)
    }
    return data
  }

  /// Bytes after the last whole record (a file cut short) are ignored.
  private static func decode(_ data: Data) -> [LocationFix] {
    let count = data.count / recordSize
    var fixes: [LocationFix] = []
    fixes.reserveCapacity(count)
    data.withUnsafeBytes { bytes in
      func bits(_ offset: Int) -> UInt64 {
        UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
      }
      for record in 0..<count {
        let start = record * recordSize
        let accuracy = Double(bitPattern: bits(start + 24))
        let altitude = Double(bitPattern: bits(start + 32))
        fixes.append(LocationFix(
          latitude: Double(bitPattern: bits(start + 8)),
          longitude: Double(bitPattern: bits(start + 16)),
          accuracy: accuracy.isNaN ? nil : accuracy,
          altitude: altitude.isNaN ? nil : altitude,
          timeMs: Int64(bitPattern: bits(start))))
      }
    }
    return fixes
  }
}
