import SwiftUI

/// Slim horizontal progress bar with an explicit track fill so it stays
/// visible on light backgrounds even at 0% (where SwiftUI's default
/// `ProgressView` track nearly disappears).
struct UsageBar: View {
    var value: Double   // 0...100
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(value, 0), 100)
            let width = geo.size.width * CGFloat(clamped) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(tint).frame(width: width)
            }
        }
        .frame(height: height)
    }
}
