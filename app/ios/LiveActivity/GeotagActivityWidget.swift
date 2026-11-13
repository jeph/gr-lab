import SwiftUI
import WidgetKit

/// How the geotagging run's notice looks on the Lock Screen and in the
/// Dynamic Island: the camera, what is happening now and a Stop button. It
/// has no text of its own; every text is the app's
/// ([GeotagActivityAttributes.ContentState]).
struct GeotagActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: GeotagActivityAttributes.self) { context in
      HStack(spacing: 12) {
        GeotagPin().font(.title2)
        VStack(alignment: .leading, spacing: 2) {
          Text(context.state.title).font(.headline).lineLimit(1)
          GeotagStatusLine(text: context.state.text)
        }
        Spacer(minLength: 8)
        GeotagStopButton(run: context.attributes.run, label: context.state.stopLabel)
      }
      .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          GeotagPin().font(.title2)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 12) {
            GeotagStatusLine(text: context.state.text)
            Spacer(minLength: 8)
            GeotagStopButton(run: context.attributes.run, label: context.state.stopLabel)
          }
        }
      } compactLeading: {
        GeotagPin()
      } compactTrailing: {
        Image(systemName: "camera.fill").accessibilityHidden(true)
      } minimal: {
        GeotagPin()
      }
    }
  }
}

/// A map pin, as the icon of Android's geotagging notification is. Like the
/// other icon it is hidden from VoiceOver, which would read the symbol's
/// English name; the texts say everything.
private struct GeotagPin: View {
  var body: some View {
    Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
  }
}

private struct GeotagStatusLine: View {
  let text: String

  var body: some View {
    // The longest status takes three lines in some languages.
    Text(text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
  }
}

private struct GeotagStopButton: View {
  let run: String
  let label: String

  var body: some View {
    Button(intent: StopGeotaggingIntent(run: run)) {
      Text(label)
    }
    .buttonStyle(.bordered)
  }
}
