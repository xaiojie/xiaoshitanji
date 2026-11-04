import SwiftUI

struct FrogSpeech: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(Theme.surface.opacity(0.94), in: .rect(cornerRadius: 18))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 12))
                    .foregroundStyle(Theme.surface).offset(x: -18, y: 8)
            }
            .shadow(color: Theme.ink.opacity(0.06), radius: 3, y: 2)
    }
}

struct FrogCallout: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Image("MilkFrogPeek").resizable().scaledToFit().frame(width: 78, height: 95)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(text).font(.headline).foregroundStyle(Theme.ink)
                if let detail { Text(detail).font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
        }
        .padding(.horizontal, 16).background(Theme.softGreen, in: .rect(cornerRadius: 24))
    }
}

struct ScanPhotoPreview: View {
    let data: Data
    var height: CGFloat = 260

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity).frame(height: height)
                .background(Theme.darkSurface, in: .rect(cornerRadius: 26))
                .overlay {
                    RoundedRectangle(cornerRadius: 20).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [28, 70]))
                        .padding(13)
                }
                .clipShape(.rect(cornerRadius: 26))
        }
    }
}

struct BrandPageTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.ink)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.mutedInk) }
        }
    }
}

struct BrandSegments<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.value }
                } label: {
                    Text(option.title).font(.system(size: 12, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == option.value { Capsule().fill(Theme.yellowGradient).shadow(color: Theme.gold.opacity(0.2), radius: 3, y: 2) }
                        }
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }.padding(4).background(Theme.softYellow.opacity(0.45), in: .capsule)
    }
}
