import SwiftUI
import UIKit

struct AboutView: View {
    @State private var copiedEmail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard
                VStack(spacing: 0) {
                    ForEach(AboutDocument.allCases) { document in
                        NavigationLink {
                            AboutDocumentView(document: document)
                        } label: {
                            HStack(spacing: 14) {
                                ObjectIcon(document.artwork, size: 42)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(document.title).font(.subheadline.weight(.semibold))
                                    Text(document.subtitle).font(.caption).foregroundStyle(Theme.mutedInk)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.mutedInk)
                            }
                            .foregroundStyle(Theme.ink).padding(.vertical, 17)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("about-\(document.rawValue)")
                        if document != AboutDocument.allCases.last { Divider().opacity(0.45) }
                    }
                }
                .padding(.horizontal, 17).background(Theme.surface, in: .rect(cornerRadius: 25))
                contactCard
                Text("© 2026 Jay He · 小食痰记")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle("关于小食痰记").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var identityCard: some View {
        VStack(spacing: 13) {
            Image("BrandMark").resizable().scaledToFill().frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 28))
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.surface.opacity(0.7), lineWidth: 2) }
                .shadow(color: Theme.ink.opacity(0.08), radius: 10, y: 5)
                .accessibilityHidden(true)
            Text("小食痰记").font(.system(.title, design: .rounded, weight: .heavy))
            Text("吃都吃了，先记一笔。")
                .font(.subheadline).foregroundStyle(Theme.mutedInk)
            Text(AppInformation.versionText).font(.caption.weight(.semibold))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Theme.surface.opacity(0.85), in: .capsule)
                .accessibilityIdentifier("aboutVersion")
            Text("作者 · \(AppInformation.author)")
                .font(.subheadline.weight(.semibold)).textSelection(.enabled)
                .accessibilityIdentifier("aboutAuthor")
        }
        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 20)
        .background(Theme.yellowGradient, in: .rect(cornerRadius: 30))
    }

    private var contactCard: some View {
        BrandSection("联系与支持", symbol: "envelope") {
            Text("功能反馈、隐私问题和数据处理请求，可以通过邮箱联系作者。")
                .font(.caption).foregroundStyle(Theme.mutedInk).lineSpacing(3)
            Text(AppInformation.contactEmail).font(.subheadline.weight(.semibold))
                .textSelection(.enabled).accessibilityIdentifier("aboutContactEmail")
            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = AppInformation.contactEmail
                    copiedEmail = true
                } label: {
                    Label(copiedEmail ? "邮箱已复制" : "复制邮箱", systemImage: copiedEmail ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("copySupportEmail")
                Link("邮件联系", destination: AppInformation.emailURL)
                    .accessibilityIdentifier("emailSupport")
            }.font(.caption.weight(.semibold)).buttonStyle(.bordered)
            Link(destination: AppInformation.supportURL) {
                Label("支持与反馈页面", systemImage: "arrow.up.right.square")
            }.font(.subheadline).accessibilityIdentifier("aboutSupportPage")
        }
    }
}

private struct AboutDocumentView: View {
    let document: AboutDocument
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FrogCallout(text: document.title, detail: document.subtitle)
                Text("更新于 \(AppInformation.updatedDate)")
                    .font(.caption).foregroundStyle(Theme.mutedInk).padding(.horizontal, 4)
                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 11) {
                        Text(section.title).font(.headline)
                        Text(section.content).font(.subheadline).lineSpacing(6)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }.contentCard()
                }
                if document == .privacy || document == .personalInformation {
                    Link("查看线上完整隐私政策", destination: AppInformation.privacyURL)
                        .font(.subheadline.weight(.semibold)).contentCard()
                }
                if document == .thirdParties {
                    VStack(alignment: .leading, spacing: 16) {
                        Link("DeepSeek 隐私政策", destination: AppInformation.deepSeekPrivacyURL)
                        Link("Apple 隐私政策", destination: AppInformation.applePrivacyURL)
                    }.font(.subheadline).contentCard()
                }
                if document == .permissions {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("打开此 App 的系统设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .yellowAction().accessibilityIdentifier("openAppPermissionSettings")
                }
                Link(destination: AppInformation.emailURL) {
                    Label(AppInformation.contactEmail, systemImage: "envelope")
                }
                .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.padding(20)
        }
        .background(Theme.background)
        .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
