import SwiftUI
import PencilKit

/// Bridges actions from SwiftUI to the StepCanvasContainer.
class CanvasActionHandler {
    fileprivate weak var container: StepCanvasContainer?

    func undo() {
        container?.canvasView.undoManager?.undo()
    }

    func redo() {
        container?.canvasView.undoManager?.redo()
    }

    func clearAll() {
        container?.clearAnnotations()
    }
}

struct StepCanvasView: UIViewRepresentable {
    let imagePath: String
    let imageStore: ImageStore
    let annotations: AnnotationData
    let isEditing: Bool
    let tool: PKTool
    let actionHandler: CanvasActionHandler
    let onAnnotationsChanged: (AnnotationData) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> StepCanvasContainer {
        let container = StepCanvasContainer()
        container.delegate = context.coordinator
        if let image = imageStore.loadImage(path: imagePath) {
            container.loadStep(imagePath: imagePath, image: image, annotations: annotations)
        }
        container.setEditing(isEditing, tool: tool)
        actionHandler.container = container
        return container
    }

    func updateUIView(_ container: StepCanvasContainer, context: Context) {
        context.coordinator.parent = self
        if container.currentImagePath != imagePath {
            if let image = imageStore.loadImage(path: imagePath) {
                container.loadStep(imagePath: imagePath, image: image, annotations: annotations)
            }
        }
        container.setEditing(isEditing, tool: tool)
        actionHandler.container = container
    }

    class Coordinator: NSObject, StepCanvasContainerDelegate {
        var parent: StepCanvasView

        init(parent: StepCanvasView) {
            self.parent = parent
        }

        func canvasAnnotationsDidChange(_ mergedAnnotation: AnnotationData) {
            parent.onAnnotationsChanged(mergedAnnotation)
        }
    }
}

protocol StepCanvasContainerDelegate: AnyObject {
    func canvasAnnotationsDidChange(_ mergedAnnotation: AnnotationData)
}

/// Layout info for the aspect-fit image within the container.
private struct ImageLayout {
    let displaySize: CGSize
    let offset: CGPoint
}

class StepCanvasContainer: UIView, PKCanvasViewDelegate {
    weak var delegate: StepCanvasContainerDelegate?

    private let imageView = UIImageView()
    private let annotationOverlayView = UIImageView()
    let canvasView = PKCanvasView()
    private(set) var currentImagePath: String?
    private var currentImageSize: CGSize = .zero
    private var existingAnnotations = AnnotationData(lines: [], labels: [])
    private var lastRenderedBounds: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .black

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        annotationOverlayView.contentMode = .scaleToFill
        annotationOverlayView.backgroundColor = .clear
        annotationOverlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(annotationOverlayView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = self
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasView)

        // All three views fill the entire container
        for view in [imageView, annotationOverlayView, canvasView] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    /// Load a new step's image and annotations. Only call when the step changes.
    func loadStep(imagePath: String, image: UIImage, annotations: AnnotationData) {
        currentImagePath = imagePath
        currentImageSize = image.size
        existingAnnotations = annotations
        imageView.image = image
        canvasView.drawing = PKDrawing()
        // Overlay rendering is deferred to layoutSubviews (bounds may be zero here)
        lastRenderedBounds = .zero
        setNeedsLayout()
    }

    func setEditing(_ editing: Bool, tool: PKTool) {
        canvasView.isUserInteractionEnabled = editing
        canvasView.tool = tool
    }

    /// Clear all annotations (existing overlay + current PK strokes).
    func clearAnnotations() {
        existingAnnotations = AnnotationData(lines: [], labels: [])
        annotationOverlayView.image = nil
        canvasView.drawing = PKDrawing()
        delegate?.canvasAnnotationsDidChange(AnnotationData(lines: [], labels: []))
    }

    /// Compute where the image appears within the container (aspect-fit centering).
    private var imageLayout: ImageLayout {
        guard currentImageSize.width > 0, currentImageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return ImageLayout(displaySize: bounds.size, offset: .zero)
        }
        let imageAspect = currentImageSize.width / currentImageSize.height
        let viewAspect = bounds.width / bounds.height
        let size: CGSize
        if imageAspect > viewAspect {
            size = CGSize(width: bounds.width, height: bounds.width / imageAspect)
        } else {
            size = CGSize(width: bounds.height * imageAspect, height: bounds.height)
        }
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        return ImageLayout(displaySize: size, offset: CGPoint(x: x, y: y))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Re-render the annotation overlay when bounds change
        if bounds != lastRenderedBounds {
            lastRenderedBounds = bounds
            renderAnnotationOverlay()
        }
    }

    /// Render existing annotations as a static image overlay.
    /// Draws at the full container size, positioning annotations over the aspect-fit image area.
    private func renderAnnotationOverlay() {
        let layout = imageLayout
        guard layout.displaySize.width > 0, layout.displaySize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            annotationOverlayView.image = nil
            return
        }
        guard !existingAnnotations.lines.isEmpty || !existingAnnotations.labels.isEmpty else {
            annotationOverlayView.image = nil
            return
        }

        let scaleX = layout.displaySize.width / currentImageSize.width
        let scaleY = layout.displaySize.height / currentImageSize.height
        let ox = layout.offset.x
        let oy = layout.offset.y

        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        annotationOverlayView.image = renderer.image { ctx in
            for line in existingAnnotations.lines {
                guard line.points.count >= 4 else { continue }
                let color = AnnotationConverter.colorFromHex(line.stroke) ?? .red
                ctx.cgContext.setStrokeColor(color.cgColor)
                ctx.cgContext.setLineWidth(CGFloat(line.strokeWidth) * scaleX)
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setLineJoin(.round)

                ctx.cgContext.move(to: CGPoint(
                    x: line.points[0] * scaleX + ox,
                    y: line.points[1] * scaleY + oy
                ))
                for i in stride(from: 2, to: line.points.count - 1, by: 2) {
                    ctx.cgContext.addLine(to: CGPoint(
                        x: line.points[i] * scaleX + ox,
                        y: line.points[i + 1] * scaleY + oy
                    ))
                }
                ctx.cgContext.strokePath()

                if let pLen = line.pointerLength, pLen > 0, line.points.count >= 4 {
                    renderArrowhead(ctx: ctx.cgContext, line: line, color: color,
                                    scaleX: scaleX, scaleY: scaleY, ox: ox, oy: oy)
                }
            }

            for label in existingAnnotations.labels {
                let scaledFontSize = CGFloat(label.fontSize) * scaleX
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: scaledFontSize),
                    .foregroundColor: AnnotationConverter.colorFromHex(label.fill) ?? .red
                ]
                let str = NSString(string: label.text)
                str.draw(at: CGPoint(x: label.x * scaleX + ox, y: label.y * scaleY + oy),
                         withAttributes: attrs)
            }
        }
    }

    private func renderArrowhead(ctx: CGContext, line: AnnotationLine, color: UIColor,
                                 scaleX: CGFloat, scaleY: CGFloat, ox: CGFloat, oy: CGFloat) {
        let points = line.points
        let n = points.count
        let endX = points[n - 2] * scaleX + ox, endY = points[n - 1] * scaleY + oy
        let prevX = points[n - 4] * scaleX + ox, prevY = points[n - 3] * scaleY + oy
        let angle = atan2(endY - prevY, endX - prevX)
        let arrowLen = (line.pointerLength ?? 10) * scaleX

        let p1 = CGPoint(
            x: endX - arrowLen * cos(angle - .pi / 6),
            y: endY - arrowLen * sin(angle - .pi / 6)
        )
        let p2 = CGPoint(
            x: endX - arrowLen * cos(angle + .pi / 6),
            y: endY - arrowLen * sin(angle + .pi / 6)
        )

        ctx.setFillColor(color.cgColor)
        ctx.move(to: CGPoint(x: endX, y: endY))
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        let layout = imageLayout
        guard layout.displaySize.width > 0, layout.displaySize.height > 0 else { return }

        // Translate the drawing so that the image top-left is at (0,0),
        // then convert from display coords to native image coords.
        let translatedDrawing = canvasView.drawing.transformed(
            using: CGAffineTransform(translationX: -layout.offset.x, y: -layout.offset.y)
        )
        let newAnnotation = AnnotationConverter.fromDrawing(
            translatedDrawing, imageSize: currentImageSize, displaySize: layout.displaySize
        )

        // Merge: existing annotations + new strokes
        let merged = AnnotationData(
            lines: existingAnnotations.lines + newAnnotation.lines,
            labels: existingAnnotations.labels + newAnnotation.labels
        )
        delegate?.canvasAnnotationsDidChange(merged)
    }
}
