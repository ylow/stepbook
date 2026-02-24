import SwiftUI

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

    var body: some View {
        GeometryReader { geo in
            if let image = imageStore.loadImage(path: step.imagePath) {
                let annotation = AnnotationData.parse(from: step.annotations)
                AnnotatedImageView(image: image, annotation: annotation)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct AnnotatedImageView: UIViewRepresentable {
    let image: UIImage
    let annotation: AnnotationData

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.image = renderAnnotatedImage()
    }

    private func renderAnnotatedImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            for line in annotation.lines {
                guard line.points.count >= 4 else { continue }
                let color = AnnotationConverter.colorFromHex(line.stroke) ?? .red
                ctx.cgContext.setStrokeColor(color.cgColor)
                ctx.cgContext.setLineWidth(CGFloat(line.strokeWidth))
                ctx.cgContext.setLineCap(.round)
                ctx.cgContext.setLineJoin(.round)

                ctx.cgContext.move(to: CGPoint(x: line.points[0], y: line.points[1]))
                for i in stride(from: 2, to: line.points.count - 1, by: 2) {
                    ctx.cgContext.addLine(to: CGPoint(x: line.points[i], y: line.points[i + 1]))
                }
                ctx.cgContext.strokePath()

                if let pLen = line.pointerLength, pLen > 0, line.points.count >= 4 {
                    drawArrowhead(ctx: ctx.cgContext, line: line, color: color)
                }
            }

            for label in annotation.labels {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: CGFloat(label.fontSize)),
                    .foregroundColor: AnnotationConverter.colorFromHex(label.fill) ?? .red
                ]
                let str = NSString(string: label.text)
                str.draw(at: CGPoint(x: label.x, y: label.y), withAttributes: attrs)
            }
        }
    }

    private func drawArrowhead(ctx: CGContext, line: AnnotationLine, color: UIColor) {
        let points = line.points
        let n = points.count
        let endX = points[n - 2], endY = points[n - 1]
        let prevX = points[n - 4], prevY = points[n - 3]
        let angle = atan2(endY - prevY, endX - prevX)
        let arrowLen = line.pointerLength ?? 10

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
