import SwiftUI
import PencilKit

struct StepCanvasView: UIViewRepresentable {
    let image: UIImage
    let annotations: AnnotationData
    let isEditing: Bool
    let tool: PKTool
    let onAnnotationsChanged: (AnnotationData) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> StepCanvasContainer {
        let container = StepCanvasContainer()
        container.delegate = context.coordinator
        container.setImage(image)
        let drawing = AnnotationConverter.toDrawing(
            annotations, imageSize: image.size, displaySize: container.displaySize
        )
        container.setDrawing(drawing)
        container.setEditing(isEditing, tool: tool)
        return container
    }

    func updateUIView(_ container: StepCanvasContainer, context: Context) {
        context.coordinator.parent = self
        container.setEditing(isEditing, tool: tool)
        if container.currentImage !== image {
            container.setImage(image)
            let drawing = AnnotationConverter.toDrawing(
                annotations, imageSize: image.size, displaySize: container.displaySize
            )
            container.setDrawing(drawing)
        }
    }

    class Coordinator: NSObject, StepCanvasContainerDelegate {
        var parent: StepCanvasView

        init(parent: StepCanvasView) {
            self.parent = parent
        }

        func canvasDrawingDidChange(_ drawing: PKDrawing, displaySize: CGSize) {
            let annotation = AnnotationConverter.fromDrawing(
                drawing, imageSize: parent.image.size, displaySize: displaySize
            )
            parent.onAnnotationsChanged(annotation)
        }
    }
}

protocol StepCanvasContainerDelegate: AnyObject {
    func canvasDrawingDidChange(_ drawing: PKDrawing, displaySize: CGSize)
}

class StepCanvasContainer: UIView, PKCanvasViewDelegate {
    weak var delegate: StepCanvasContainerDelegate?

    private let imageView = UIImageView()
    let canvasView = PKCanvasView()
    private(set) var currentImage: UIImage?
    private(set) var displaySize: CGSize = CGSize(width: 300, height: 300)

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

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = self
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setImage(_ image: UIImage) {
        currentImage = image
        imageView.image = image
        setNeedsLayout()
    }

    func setDrawing(_ drawing: PKDrawing) {
        canvasView.drawing = drawing
    }

    func setEditing(_ editing: Bool, tool: PKTool) {
        canvasView.isUserInteractionEnabled = editing
        canvasView.tool = tool
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = currentImage, bounds.width > 0, bounds.height > 0 else { return }
        let imageAspect = image.size.width / image.size.height
        let viewAspect = bounds.width / bounds.height
        if imageAspect > viewAspect {
            displaySize = CGSize(width: bounds.width, height: bounds.width / imageAspect)
        } else {
            displaySize = CGSize(width: bounds.height * imageAspect, height: bounds.height)
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        delegate?.canvasDrawingDidChange(canvasView.drawing, displaySize: displaySize)
    }
}
