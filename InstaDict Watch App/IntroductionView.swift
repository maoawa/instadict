import SwiftUI

struct IntroductionView: View {
    @ScaledMetric(relativeTo: .title3) private var titleSize = 20
    @ScaledMetric(relativeTo: .footnote) private var textSize = 13
    @ScaledMetric(relativeTo: .caption2) private var tipSize = 12
    let onBegin: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "character.book.closed.fill")
                            .foregroundStyle(.tint)
                        Text("InstaDict")
                            .font(.system(size: titleSize, weight: .bold, design: .serif))
                    }
                    Text("Send a dictionary from iPhone once. Then open and type offline.")
                        .font(.system(size: textSize)).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "square.and.pencil").frame(width: 22)
                        Text("Look up a new word")
                    }
                    .font(.system(size: tipSize))
                    HStack(alignment: .top, spacing: 10) {
                        Text("中").fontWeight(.semibold).frame(width: 22)
                        Text("English–Chinese")
                    }
                    .font(.system(size: tipSize))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
            .clipped()
            Button("Look up a word", action: onBegin)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .foregroundStyle(.black)
                .accessibilityIdentifier("beginLookup")
        }
        .accessibilityIdentifier("introduction")
    }
}
