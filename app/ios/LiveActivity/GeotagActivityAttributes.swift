import ActivityKit
import AppIntents

// Compiled into the app and into the LiveActivity extension: iOS matches the
// activity the app starts to the extension's views by this type, and runs
// the Stop button's intent in the app.

/// The Live Activity of a held geotagging run: the run's notice, which on
/// Android is a notification. Everything it shows can change during the run
/// (the status line, the camera's name, the app's language), so all of it is
/// content.
@available(iOS 17.0, *)
struct GeotagActivityAttributes: ActivityAttributes {
  /// Names the run to the app (`GrCameraRunNotice.run`); never shown. The
  /// Stop button hands it back, also after the app that started the
  /// activity has ended.
  var run: String

  /// The notice's texts, from the app's messages in the user's language.
  struct ContentState: Codable, Hashable {
    /// First line: the camera the location goes to.
    var title: String

    /// Second line: what is happening now.
    var text: String

    /// Label of the button that turns live geotagging off.
    var stopLabel: String
  }
}

/// The Stop button of the activity. A `LiveActivityIntent` runs in the app's
/// process, which iOS starts in the background if it is not running.
@available(iOS 17.0, *)
struct StopGeotaggingIntent: LiveActivityIntent {
  // Never shown: the intent is not discoverable, so the Shortcuts app does
  // not list it. The button's label comes with the activity's content.
  static let title: LocalizedStringResource = "Stop geotagging"
  static let isDiscoverable = false

  /// What Stop does for a run; set by the app when it starts and nil in
  /// the extension, where the intent never runs.
  @MainActor static var onPerform: ((String) -> Void)?

  /// The run of the activity the button is on.
  @Parameter(title: "Run")
  var run: String

  init() {}

  init(run: String) {
    self.run = run
  }

  func perform() async throws -> some IntentResult {
    let run = run
    await MainActor.run { Self.onPerform?(run) }
    return .result()
  }
}
