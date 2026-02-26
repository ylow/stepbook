import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PortraitHostingController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        // Wrap in a portrait-only container so the camera works
        // correctly even when launched from landscape orientation.
        let host = PortraitHostingController()
        host.modalPresentationStyle = .fullScreen
        host.childPicker = picker
        return host
    }

    func updateUIViewController(_ uiViewController: PortraitHostingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView

        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// A container view controller that forces portrait orientation
/// for UIImagePickerController camera, which doesn't support landscape on iPhone.
class PortraitHostingController: UIViewController {
    var childPicker: UIImagePickerController?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let picker = childPicker, picker.presentingViewController == nil {
            present(picker, animated: false)
        }
    }
}
