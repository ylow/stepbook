import SwiftUI
import UIKit

struct StepViewerView: View {
    let steps: [Step]
    @Binding var selectedIndex: Int
    let imageStore: ImageStore

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                StepPageView(step: step, imageStore: imageStore)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
    }
}

struct StepPageView: View {
    let step: Step
    let imageStore: ImageStore
    @State private var renderedImage: UIImage?
    @State private var zoomId = UUID()

    var body: some View {
        Group {
            if let rendered = renderedImage {
                ZoomableImageView(image: rendered)
                    .id(zoomId)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: "\(step.id)|\(step.annotations)") {
            renderedImage = await renderAsync()
            zoomId = UUID() // reset zoom when image changes
        }
    }

    /// Render the annotated image off the main thread.
    private func renderAsync() async -> UIImage? {
        let path = step.imagePath
        let annotationsStr = step.annotations
        let store = imageStore

        return await Task.detached(priority: .userInitiated) {
            let maxDim = await maxPixelDimension()
            let maxSize = CGSize(width: maxDim, height: maxDim)

            guard let thumbnail = store.loadThumbnail(path: path, maxSize: maxSize) else {
                return nil
            }

            let annotation = AnnotationData.parse(from: annotationsStr)
            let nativeSize = nativeImageSize(store: store, path: path)

            return renderAnnotatedImage(
                image: thumbnail,
                annotation: annotation,
                nativeImageSize: nativeSize
            )
        }.value
    }

    @MainActor
    private func maxPixelDimension() -> CGFloat {
        let screen = UIScreen.main
        return max(screen.bounds.width, screen.bounds.height) * screen.scale
    }

    /// Get the native image dimensions without loading the full image into memory.
    /// Accounts for EXIF orientation so width/height match UIImage.size.
    private nonisolated func nativeImageSize(store: ImageStore, path: String) -> CGSize {
        let url = store.imageURL(path: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return .zero
        }
        // EXIF orientations 5-8 swap width and height
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation >= 5 && orientation <= 8 {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    /// Render annotations onto a (possibly downscaled) image.
    private nonisolated func renderAnnotatedImage(image: UIImage, annotation: AnnotationData, nativeImageSize: CGSize) -> UIImage {
        let renderSize = image.size
        let scaleX: CGFloat = nativeImageSize.width > 0 ? renderSize.width / nativeImageSize.width : 1
        let scaleY: CGFloat = nativeImageSize.height > 0 ? renderSize.height / nativeImageSize.height : 1

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: renderSize))

            for line in annotation.lines {
                guard line.points.count >= 4 else { continue }
                let color = AnnotationConverter.colorFromHex(line.stroke) ?? .red
                ctx.cgContext.setStrokeColor(color.cgColor)
                ctx.cgContext.setLineWidth(CGFloat(line.strokeWidth) * scaleX)
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setLineJoin(.round)

                ctx.cgContext.move(to: CGPoint(
                    x: line.points[0] * scaleX,
                    y: line.points[1] * scaleY
                ))
                for i in stride(from: 2, to: line.points.count - 1, by: 2) {
                    ctx.cgContext.addLine(to: CGPoint(
                        x: line.points[i] * scaleX,
                        y: line.points[i + 1] * scaleY
                    ))
                }
                ctx.cgContext.strokePath()

                if let pLen = line.pointerLength, pLen > 0, line.points.count >= 4 {
                    Self.renderArrowhead(ctx: ctx.cgContext, line: line, color: color, scaleX: scaleX, scaleY: scaleY)
                }
            }

            for label in annotation.labels {
                let scaledFontSize = CGFloat(label.fontSize) * scaleX
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: scaledFontSize),
                    .foregroundColor: AnnotationConverter.colorFromHex(label.fill) ?? .red
                ]
                let str = NSString(string: label.text)
                str.draw(at: CGPoint(x: label.x * scaleX, y: label.y * scaleY), withAttributes: attrs)
            }
        }
    }

    private static func renderArrowhead(ctx: CGContext, line: AnnotationLine, color: UIColor, scaleX: CGFloat, scaleY: CGFloat) {
        let points = line.points
        let n = points.count
        let endX = points[n - 2] * scaleX, endY = points[n - 1] * scaleY
        let prevX = points[n - 4] * scaleX, prevY = points[n - 3] * scaleY
        let angle = atan2(endY - prevY, endX - prevX)
        let arrowLen = (line.pointerLength ?? 10) * scaleX

        let p1 = CGPoint(
            x: endX - arrowLen * cos(angle - Double.pi / 6),
            y: endY - arrowLen * sin(angle - Double.pi / 6)
        )
        let p2 = CGPoint(
            x: endX - arrowLen * cos(angle + Double.pi / 6),
            y: endY - arrowLen * sin(angle + Double.pi / 6)
        )

        ctx.setFillColor(color.cgColor)
        ctx.move(to: CGPoint(x: endX, y: endY))
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])

        // Double-tap to toggle zoom
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let zoomRect = CGRect(
                    x: location.x - 50,
                    y: location.y - 50,
                    width: 100,
                    height: 100
                )
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}
