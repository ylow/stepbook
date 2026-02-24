import SwiftUI
import PencilKit

enum DrawingTool: String, CaseIterable {
    case pen = "Pen"
    case marker = "Marker"
    case pencil = "Pencil"
    case eraser = "Eraser"

    var icon: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        }
    }

    func toPKTool(color: UIColor, width: CGFloat) -> PKTool {
        switch self {
        case .pen: return PKInkingTool(.pen, color: color, width: width)
        case .marker: return PKInkingTool(.marker, color: color, width: width)
        case .pencil: return PKInkingTool(.pencil, color: color, width: width)
        case .eraser: return PKEraserTool(.vector)
        }
    }
}

enum StrokeWidth: CGFloat, CaseIterable {
    case thin = 2
    case medium = 4
    case thick = 8

    var label: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }
}

struct AnnotationToolbar: View {
    @Binding var selectedTool: DrawingTool
    @Binding var selectedColor: Color
    @Binding var strokeWidth: StrokeWidth
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onClearAll: () -> Void

    @State private var showClearConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(selectedTool == tool ? .white : .primary)
                        .frame(width: 36, height: 36)
                        .background(selectedTool == tool ? Color.blue : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider().frame(height: 24)

            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)

            Menu {
                ForEach(StrokeWidth.allCases, id: \.self) { width in
                    Button {
                        strokeWidth = width
                    } label: {
                        Label(width.label, systemImage: "line.diagonal")
                    }
                }
            } label: {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
            }

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }
            Button {
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
            }
            .confirmationDialog("Clear all annotations?", isPresented: $showClearConfirmation) {
                Button("Clear All", role: .destructive, action: onClearAll)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
