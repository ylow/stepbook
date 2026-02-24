import SwiftUI
import PhotosUI
import PencilKit

struct SequenceEditorView: View {
    let sequenceId: String
    let book: Book
    @Environment(AppDatabase.self) private var appDb
    @Environment(\.dismiss) private var dismiss

    @State private var sequence: Sequence?
    @State private var steps: [Step] = []
    @State private var selectedStepIndex: Int = 0
    @State private var editMode = false
    @State private var overlayVisible = true
    @State private var showNotes = false
    @State private var captionExpanded = false

    // Drawing state
    @State private var selectedTool: DrawingTool = .pen
    @State private var selectedColor: Color = .red
    @State private var strokeWidth: StrokeWidth = .medium

    // Photo picker
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingCamera = false

    // Canvas actions (undo/redo bridge)
    @State private var canvasActionHandler = CanvasActionHandler()

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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if steps.isEmpty {
                emptyState
            } else if editMode {
                editModeView
            } else {
                viewModeView
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: selectedPhotos) { _, items in
            Task { await importPhotos(items) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            headerBar
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
                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text("\(selectedStepIndex + 1) / \(steps.count)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding()
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

    private var editModeView: some View {
        VStack(spacing: 0) {
            headerBar

            AnnotationToolbar(
                selectedTool: $selectedTool,
                selectedColor: $selectedColor,
                strokeWidth: $strokeWidth,
                onUndo: { canvasActionHandler.undo() },
                onRedo: { canvasActionHandler.redo() },
                onClearAll: { canvasActionHandler.clearAll() }
            )

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
                .id(step.id) // Recreate canvas when step changes
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }

            if showNotes, let step = currentStep {
                StepNotesEditor(
                    notes: step.notes,
                    onSave: { notes in
                        saveNotes(stepId: step.id, notes: notes)
                    }
                )
                .id(step.id) // Force recreation when step changes
                .frame(height: 120)
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
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

            Spacer()

            if let seq = sequence {
                Text(seq.title)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 16) {
                if editMode {
                    Button {
                        showNotes.toggle()
                    } label: {
                        Image(systemName: showNotes ? "note.text.badge.plus" : "note.text")
                    }
                }

                Menu {
                    PhotosPicker(selection: $selectedPhotos, matching: .images) {
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
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Add Photos Buttons

    private var addPhotosButtons: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhotos, matching: .images) {
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

struct StepNotesEditor: View {
    @State private var text: String
    let onSave: (String) -> Void

    init(notes: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: notes)
        self.onSave = onSave
    }

    var body: some View {
        TextEditor(text: $text)
            .padding(8)
            .background(.ultraThinMaterial)
            .onChange(of: text) { _, newValue in
                onSave(newValue)
            }
    }
}
