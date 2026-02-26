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
    var axis: Axis = .horizontal

    @State private var showClearConfirmation = false

    private var isCompact: Bool { axis == .vertical }
    private var btnSize: CGFloat { isCompact ? 32 : 36 }
    private var iconSize: CGFloat { isCompact ? 16 : 18 }

    var body: some View {
        if isCompact {
            compactVerticalBody
        } else {
            horizontalBody
        }
    }

    // MARK: - Horizontal (Portrait)

    private var horizontalBody: some View {
        HStack(spacing: 0) {
            // Tool group
            HStack(spacing: 10) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    toolButton(tool)
                }
            }

            Divider().frame(height: 24).padding(.horizontal, 10)

            // Color & width group
            HStack(spacing: 10) {
                ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30, height: 30)
                strokeWidthMenu
            }

            Divider().frame(height: 24).padding(.horizontal, 10)

            // Actions group
            HStack(spacing: 10) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: iconSize))
                        .frame(width: btnSize, height: btnSize)
                }
                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: iconSize))
                        .frame(width: btnSize, height: btnSize)
                }
                clearButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Vertical (Landscape)

    private var compactVerticalBody: some View {
        VStack(spacing: 1) {
            // Tool group
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            Divider().frame(width: 24).padding(.vertical, 2)

            // Color & width
            VStack(spacing: 0) {
                ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                strokeWidthMenu
            }

            // Actions
            VStack(spacing: 0) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14))
                        .frame(width: btnSize, height: btnSize)
                }
                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 14))
                        .frame(width: btnSize, height: btnSize)
                }
            }
            clearButton
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Shared Components

    private func toolButton(_ tool: DrawingTool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.icon)
                .font(.system(size: iconSize))
                .foregroundStyle(selectedTool == tool ? .white : .primary)
                .frame(width: btnSize, height: btnSize)
                .background(selectedTool == tool ? Color.blue : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var strokeWidthMenu: some View {
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
                .font(.system(size: isCompact ? 13 : 16))
                .frame(width: btnSize, height: btnSize)
        }
    }

    private var clearButton: some View {
        Button {
            showClearConfirmation = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: isCompact ? 13 : iconSize))
                .frame(width: btnSize, height: btnSize)
        }
        .confirmationDialog("Clear all annotations?", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive, action: onClearAll)
        }
    }
}
