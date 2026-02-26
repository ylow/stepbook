import SwiftUI
import PhotosUI
import PencilKit

struct SequenceEditorView: View {
    let sequenceId: String
    let book: Book
    @Environment(AppDatabase.self) private var appDb
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var sequence: Sequence?
    @State private var steps: [Step] = []
    @State private var selectedStepIndex: Int = 0
    @State private var editMode = false
    @State private var overlayVisible = true
    @State private var captionExpanded = false

    // Drawing state
    @State private var selectedTool: DrawingTool = .pen
    @State private var selectedColor: Color = .red
    @State private var strokeWidth: StrokeWidth = .medium

    // Photo picker
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?

    // Canvas actions (undo/redo bridge)
    @State private var canvasActionHandler = CanvasActionHandler()

    // Notes sheet (landscape)
    @State private var showNotesSheet = false

    // Export
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    var currentStep: Step? {
        guard selectedStepIndex >= 0, selectedStepIndex < steps.count else { return nil }
        return steps[selectedStepIndex]
    }

    private var currentPKTool: PKTool {
        let uiColor = UIColor(selectedColor)
        return selectedTool.toPKTool(color: uiColor, width: strokeWidth.rawValue)
    }

    /// Show the system navigation bar for edit/empty states (proper safe area handling),
    /// hide it for view mode (which uses its own floating overlay).
    private var showSystemBar: Bool {
        editMode || steps.isEmpty
    }

    var body: some View {
        Group {
            if steps.isEmpty {
                emptyState
            } else if editMode {
                editModeView
            } else {
                viewModeView
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(showSystemBar ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if showSystemBar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode {
                        Button("Done") {
                            editMode = false
                            overlayVisible = true
                        }
                        .fontWeight(.semibold)
                    } else {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if let seq = sequence {
                        Text(seq.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                            Button {
                                showingPhotoPicker = true
                            } label: {
                                Label("Photo Library", systemImage: "photo.on.rectangle")
                            }
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                            }
                            if !steps.isEmpty {
                                Divider()
                                if let url = exportURL {
                                    ShareLink(item: url) {
                                        Label("Share Export", systemImage: "square.and.arrow.up")
                                    }
                                } else {
                                    Button {
                                        exportSequence()
                                    } label: {
                                        Label("Export", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotos, matching: .images)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView(image: $cameraImage)
        }
        .sheet(isPresented: $showNotesSheet) {
            if let step = currentStep {
                NotesSheetView(
                    notes: step.notes,
                    onSave: { notes in
                        saveNotes(stepId: step.id, notes: notes)
                    }
                )
            }
        }
        .task { await load() }
        .onChange(of: selectedPhotos) { _, items in
            Task { await importPhotos(items) }
        }
        .onChange(of: cameraImage) { _, image in
            if let image {
                Task { await importCameraPhoto(image) }
                cameraImage = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ContentUnavailableView(
                "No Steps Yet",
                systemImage: "photo.badge.plus",
                description: Text("Add photos to create steps")
            )
            Spacer()
            addPhotosButtons
        }
    }

    // MARK: - View Mode

    private var viewModeView: some View {
        ZStack {
            if let store = imageStore {
                StepViewerView(
                    steps: steps,
                    selectedIndex: $selectedStepIndex,
                    imageStore: store
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        overlayVisible.toggle()
                    }
                }
            }

            if overlayVisible {
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                        Text("\(selectedStepIndex + 1) / \(steps.count)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5))
                    Spacer()
                }
            }

            if let step = currentStep, !step.notes.isEmpty, overlayVisible {
                VStack {
                    Spacer()
                    Text(step.notes)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(captionExpanded ? nil : 3)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.7))
                        .background(.ultraThinMaterial)
                        .onTapGesture { captionExpanded.toggle() }
                }
            }

            // Edit FAB
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { editMode = true } label: {
                        Image(systemName: "pencil")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding()
                    .padding(.bottom, currentStep?.notes.isEmpty == false ? 60 : 0)
                }
            }
        }
    }

    // MARK: - Edit Mode

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var editModeView: some View {
        VStack(spacing: 0) {
            if isLandscape {
                // Landscape: toolbar on left, canvas in center, notes on right
                HStack(spacing: 0) {
                    AnnotationToolbar(
                        selectedTool: $selectedTool,
                        selectedColor: $selectedColor,
                        strokeWidth: $strokeWidth,
                        onUndo: { canvasActionHandler.undo() },
                        onRedo: { canvasActionHandler.redo() },
                        onClearAll: { canvasActionHandler.clearAll() },
                        axis: .vertical
                    )
                    .padding(.top, 14)

                    canvasView

                    if let step = currentStep {
                        NotesSidebar(
                            notes: step.notes,
                            onTap: { showNotesSheet = true }
                        )
                        .id(step.id)
                        .frame(width: 200)
                    }
                }
            } else {
                // Portrait: original vertical stack
                AnnotationToolbar(
                    selectedTool: $selectedTool,
                    selectedColor: $selectedColor,
                    strokeWidth: $strokeWidth,
                    onUndo: { canvasActionHandler.undo() },
                    onRedo: { canvasActionHandler.redo() },
                    onClearAll: { canvasActionHandler.clearAll() }
                )

                canvasView

                if let step = currentStep {
                    NotesSidebar(
                        notes: step.notes,
                        onTap: { showNotesSheet = true }
                    )
                    .id(step.id)
                    .frame(height: 80)
                }
            }

            if let store = imageStore {
                FilmstripView(
                    steps: steps,
                    selectedId: currentStep?.id,
                    imageStore: store,
                    onSelect: { id in
                        if let idx = steps.firstIndex(where: { $0.id == id }) {
                            selectedStepIndex = idx
                        }
                    },
                    onDelete: { id in deleteStep(id) }
                )
            }
        }
    }

    @ViewBuilder
    private var canvasView: some View {
        if let step = currentStep, let store = imageStore {
            StepCanvasView(
                imagePath: step.imagePath,
                imageStore: store,
                annotations: AnnotationData.parse(from: step.annotations),
                isEditing: true,
                tool: currentPKTool,
                actionHandler: canvasActionHandler,
                onAnnotationsChanged: { annotation in
                    saveAnnotations(stepId: step.id, annotation: annotation)
                }
            )
            .id(step.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        }
    }

    // headerBar removed — now using system toolbar items (see body)

    // MARK: - Add Photos Buttons

    private var addPhotosButtons: some View {
        HStack(spacing: 16) {
            Button {
                showingPhotoPicker = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Button {
                showingCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Image Store

    private var imageStore: ImageStore? {
        guard let db = appDb.activeDatabase else { return nil }
        return ImageStore(imagesDirectory: db.imagesDirectory)
    }

    // MARK: - Data Operations

    private func load() async {
        guard let db = appDb.activeDatabase else { return }
        guard let (seq, s) = try? db.fetchSequenceWithSteps(id: sequenceId) else { return }
        sequence = seq
        steps = s
        if !steps.isEmpty && selectedStepIndex >= steps.count {
            selectedStepIndex = 0
        }
    }

    private func saveAnnotations(stepId: String, annotation: AnnotationData) {
        guard let db = appDb.activeDatabase else { return }
        let jsonString = annotation.toJSONString()
        _ = try? db.updateStep(id: stepId, annotations: jsonString, notes: nil)
        // Update in-memory steps so view mode renders the latest annotations
        if let idx = steps.firstIndex(where: { $0.id == stepId }) {
            steps[idx].annotations = jsonString
        }
    }

    private func saveNotes(stepId: String, notes: String) {
        guard let db = appDb.activeDatabase else { return }
        _ = try? db.updateStep(id: stepId, annotations: nil, notes: notes)
        // Update in-memory steps so view mode caption bar reflects changes
        if let idx = steps.firstIndex(where: { $0.id == stepId }) {
            steps[idx].notes = notes
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard let db = appDb.activeDatabase, let store = imageStore else { return }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            let stepId = UUID().uuidString
            guard let imagePath = try? store.saveImage(image, sequenceId: sequenceId, stepId: stepId) else { continue }
            _ = try? db.createStep(sequenceId: sequenceId, imagePath: imagePath)
        }
        selectedPhotos = []
        await load()
        if !steps.isEmpty {
            selectedStepIndex = steps.count - 1
        }
        editMode = true
    }

    private func importCameraPhoto(_ image: UIImage) async {
        guard let db = appDb.activeDatabase, let store = imageStore else { return }
        let stepId = UUID().uuidString
        guard let imagePath = try? store.saveImage(image, sequenceId: sequenceId, stepId: stepId) else { return }
        _ = try? db.createStep(sequenceId: sequenceId, imagePath: imagePath)
        await load()
        if !steps.isEmpty {
            selectedStepIndex = steps.count - 1
        }
        editMode = true
    }

    private func deleteStep(_ stepId: String) {
        guard let db = appDb.activeDatabase else { return }
        if let step = steps.first(where: { $0.id == stepId }) {
            imageStore?.deleteImage(path: step.imagePath)
        }
        try? db.deleteStep(id: stepId)
        Task { await load() }
    }

    private func exportSequence() {
        guard let db = appDb.activeDatabase, let store = imageStore else { return }
        let service = ImportExportService(database: db, imageStore: store)
        guard let url = try? service.exportSequence(id: sequenceId) else { return }
        exportURL = url
    }
}

/// Read-only notes preview. Tap to edit in a sheet.
struct NotesSidebar: View {
    let notes: String
    let onTap: () -> Void

    var body: some View {
        ScrollView {
            Text(notes.isEmpty ? "Tap to add notes..." : notes)
                .font(.subheadline)
                .foregroundStyle(notes.isEmpty ? Color.secondary : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(white: 0.15))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Sheet for editing notes in landscape mode (has its own keyboard handling).
struct NotesSheetView: View {
    @State private var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(notes: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: notes)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding(8)
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            onSave(text)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium])
    }
}
