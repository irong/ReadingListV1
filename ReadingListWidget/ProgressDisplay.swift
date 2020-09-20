import Foundation
import SwiftUI

struct ProgressDisplay: View {
    let progressPercentage: Int
    let height: CGFloat = 2

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            ProgressBar(currentProgress: CGFloat(Double(progressPercentage) / 100))
                .padding([.leading, .trailing], 8)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            Text("\(progressPercentage)%")
                .font(.caption2)
                .foregroundColor(Color(.secondaryLabel))
                .fontWeight(.medium)
        }
    }
}
