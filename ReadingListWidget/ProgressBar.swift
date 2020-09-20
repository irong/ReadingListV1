import Foundation
import SwiftUI

struct ProgressBar: View {
    let currentProgress: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1)
                    .foregroundColor(Color(.tertiarySystemFill))
                    .frame(width: geo.size.width, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .foregroundColor(.blue)
                    .frame(width: geo.size.width * currentProgress, height: 2)
            }
        }
    }
}
