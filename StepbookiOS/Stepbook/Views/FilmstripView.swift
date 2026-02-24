import SwiftUI

struct FilmstripView: View {
    let steps: [Step]
    let selectedId: String?
    let imageStore: ImageStore
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(steps) { step in
                        FilmstripThumb(
                            step: step,
                            isSelected: step.id == selectedId,
                            imageStore: imageStore,
                            onTap: { onSelect(step.id) },
                            onDelete: { onDelete(step.id) }
                        )
                        .id(step.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: 88)
            .background(.ultraThinMaterial)
            .onChange(of: selectedId) { _, newId in
                if let newId {
                    withAnimation {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }
}

struct FilmstripThumb: View {
    let step: Step
    let isSelected: Bool
    let imageStore: ImageStore
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                if let thumb = imageStore.loadThumbnail(
                    path: step.imagePath,
                    maxSize: CGSize(width: 120, height: 80)
                ) {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .frame(width: 80, height: 60)
                }
                Text("\(step.orderIndex + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
