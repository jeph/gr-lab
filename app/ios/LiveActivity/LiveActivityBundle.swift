import SwiftUI
import WidgetKit

/// GR Photo's widget extension. It holds no Home Screen widget, only the
/// views of the app's Live Activities.
@main
struct LiveActivityBundle: WidgetBundle {
  var body: some Widget {
    GeotagActivityWidget()
  }
}
