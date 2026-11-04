import SwiftUI
import NutritionCore

struct SmokingPackPickerView: View {
    @Environment(DiaryModel.self) private var diary
    @Environment(\.dismiss) private var dismiss
    @State private var addingCigarette = false
    @State private var packCountBeforeAdding = 0
    @State private var errorMessage: String?

    private var journal: SmokingDiary { diary.document.smoking }
    private var openedPacks: [CigarettePack] { journal.packs.reversed().filter { journal.remaining(in: $0.id) > 0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !openedPacks.isEmpty { openedPackSection }
                    savedCigaretteSection
                    Button("AI 识别新香烟", systemImage: "camera.viewfinder") {
                        packCountBeforeAdding = journal.packs.count
                        addingCigarette = true
                    }
                    .yellowAction().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("recognizeNewCigarette")
                    Text("已开封的烟包保留各自余量。同款开新包时使用已有识别资料，初始为20根。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    if let error = diary.loadError ?? errorMessage { ErrorNotice(message: error).contentCard() }
                }.padding(20)
            }
            .background(Theme.background).navigationTitle("换一包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $addingCigarette, onDismiss: {
                if journal.packs.count > packCountBeforeAdding { dismiss() }
            }) { SmokingPackEditorView() }
        }
    }

    private var openedPackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("切回已开封烟包").font(.title3.bold()).padding(.horizontal, 4)
            ForEach(openedPacks) { pack in
                HStack(spacing: 14) {
                    cigaretteIcon(pack)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pack.product.name).font(.headline)
                        Text("剩余 \(journal.remaining(in: pack.id)) 根 · \(pack.openedAt.formatted(.dateTime.month().day().hour().minute()))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if pack.id == journal.activePackID {
                        Text("当前").font(.caption).foregroundStyle(Theme.olive)
                    } else {
                        Button("切换") { activate(pack) }.font(.caption.weight(.semibold)).buttonStyle(.glass)
                    }
                }.contentCard()
            }
        }
    }

    private var savedCigaretteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("从我的香烟开一包").font(.title3.bold()).padding(.horizontal, 4)
            ForEach(journal.savedCigarettes) { saved in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        cigaretteIcon(saved)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(saved.product.name).font(.headline)
                            Text("已有 AI 识别资料 · 20 根 / 包").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    Button("同款开新一包", systemImage: "rectangle.stack.badge.plus") { openAnother(saved) }
                        .buttonStyle(.glass).font(.subheadline.weight(.semibold))
                }.contentCard()
            }
            if journal.savedCigarettes.isEmpty {
                HealthEmptyView(symbol: "rectangle.stack", title: "先识别一种香烟", detail: "识别保存后，以后换同款直接在这里选择。")
                    .contentCard()
            }
        }
    }

    private func cigaretteIcon(_ pack: CigarettePack) -> some View {
        Group {
            if let data = pack.photoJPEG, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "rectangle.stack.fill").font(.title2).foregroundStyle(Theme.olive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.accent.opacity(0.08))
            }
        }.frame(width: 48, height: 58).clipShape(.rect(cornerRadius: 12)).accessibilityHidden(true)
    }

    private func activate(_ pack: CigarettePack) {
        do { try diary.activateSmokingPack(pack.id); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }

    private func openAnother(_ saved: CigarettePack) {
        do { try diary.openAnotherSmokingPack(like: saved.id); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}
