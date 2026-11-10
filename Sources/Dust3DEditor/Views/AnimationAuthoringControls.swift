import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Native controls render the tested workflow; no view callback enters the engine directly.
struct AnimationAuthoringControls: View {
    let store: EditorStore
    @Bindable var workflow: EditorAnimationAuthoringWorkflow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workflow.isActive {
                draftForm.disabled(workflow.isSubmitting || !workflow.isCurrent)
                if let message = workflow.validationMessage {
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(action: workflow.cancel) { Text("Cancel").frame(minWidth: 40, minHeight: 40) }
                        .disabled(workflow.isSubmitting)
                    Spacer()
                    if workflow.isSubmitting {
                        ProgressView().controlSize(.small).accessibilityLabel("Applying animation settings")
                    }
                    Button(action: workflow.submit) { Text(applyTitle).frame(minWidth: 40, minHeight: 40) }
                        .buttonStyle(.borderedProminent).disabled(!workflow.canApply)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .help("Apply animation settings (Command-Return)")
                }
            } else {
                availability
                Button(action: workflow.creationAction()) {
                    Label("New Animation", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 40)
                }.disabled(!workflow.canBeginCreation).accessibilityLabel("Create stored animation")
                HStack(spacing: 8) {
                    Button(action: workflow.editAction(.type)) {
                        Text("Change Type").frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .disabled(!workflow.canBeginType).accessibilityLabel("Change stored animation type")
                    Button(action: workflow.editAction(.parameters)) {
                        Text("Parameters").frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .disabled(!workflow.canBeginParameters).accessibilityLabel("Edit stored animation parameters")
                }
                if workflow.canBeginType && !workflow.canBeginParameters {
                    Text("Choose a declared type to edit its controls. Unsupported stored values are kept.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.bordered)
        .onExitCommand { workflow.cancel() }
    }

    @ViewBuilder private var availability: some View {
        let state = store.authoringCatalog
        if state.isLoading {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading type definitions…")
            }.font(.caption)
        } else if let issue = state.issue {
            Text(EditorStore.message(issue)).font(.caption).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                state.load()
            } label: {
                Text("Retry Definitions").frame(minHeight: 40)
            }.disabled(!state.canLoad)
        } else if state.catalog?.clips.isEmpty == true {
            Text("No declared animation types are available.").font(.caption).foregroundStyle(.secondary)
        } else if state.catalog != nil, store.animationSnapshot != nil, workflow.creationClips.isEmpty {
            Text("Choose a rig with declared animation types to create a new animation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var draftForm: some View {
        switch workflow.mode {
        case .idle: EmptyView()
        case .create:
            Text("New animation").font(.subheadline)
            AnimationNameField(text: $workflow.name, onSubmit: workflow.submit, onCancel: workflow.cancel)
                .frame(height: 44).focusedValue(\.editorTextEditing, true)
            typePicker
            if let clip = workflow.selectedClip {
                Text("Declared duration: \(clip.seconds.formatted()) s · \(clip.samples) samples")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Text("Create with the displayed type’s initial settings, then edit Parameters as needed.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            }
        case .type:
            Text("Type for \(workflow.sourceTitle)").font(.subheadline).lineLimit(2)
            typePicker
            Text("Changing type keeps the other stored parameters.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .parameters:
            Text("Parameters for \(workflow.sourceTitle)").font(.subheadline).lineLimit(2)
            if let draft = workflow.parameterDraft {
                Text(draft.clip.type).font(.caption).textSelection(.enabled)
                Text("Unchanged settings and unsupported values are kept. Default removes a stored override.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                timingFields(draft.timing, seconds: draft.clip.seconds, frames: draft.clip.samples)
                surfacePicker(draft.surfaceMaterials)
                ForEach(draft.clip.controls.indices, id: \.self) { index in
                    let control = draft.clip.controls[index]
                    Divider()
                    numericField(
                        name: control.name, label: control.label, defaultText: String(control.defaultParameter),
                        supported: {
                            guard let value = Double($0) else { return false }
                            return (try? control.slider(for: value)) != nil
                        })
                    if control.minimumSlider < control.maximumSlider {
                        let setPosition = workflow.parameterAction { workflow, value in
                            workflow.setSlider(name: control.name, index: value)
                        }
                        Slider(
                            value: Binding(
                                get: { sliderPosition(control) ?? Double(control.defaultSlider) },
                                set: { setPosition($0) }),
                            in: Double(control.minimumSlider)...Double(control.maximumSlider), step: 1
                        )
                        .frame(minHeight: 40).accessibilityLabel(control.label)
                        .help("\(control.label) · \(control.name)")
                        .disabled(sliderPosition(control) == nil)
                    }
                }
            } else if let draft = workflow.unknownParameterDraft {
                Text(workflow.sourceType ?? "").font(.caption).textSelection(.enabled)
                Text("Timing and surface material are editable for this type. Other parameters are kept.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                timingFields(draft.timing, seconds: draft.defaultSeconds, frames: draft.defaultFrames)
                surfacePicker(draft.surfaceMaterials)
            }
        }
    }

    @ViewBuilder private func timingFields(_ timing: AnimationTimingDefinition, seconds: Double, frames: Int)
        -> some View
    {
        numericField(
            name: "durationSeconds", label: "Duration (seconds)", defaultText: String(seconds),
            supported: { text in
                guard let value = Double(text) else { return false }
                return (try? timing.validate(seconds: value, frames: Double(timing.minimumFrames))) != nil
            })
        numericField(
            name: "frameCount", label: "Sample count", defaultText: String(frames),
            supported: { text in
                guard let value = Double(text) else { return false }
                return (try? timing.validate(seconds: timing.minimumSeconds, frames: value)) != nil
            })
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Stored type", selection: $workflow.selectedType) {
                Text("Choose a type").tag([UInt8]()).disabled(true)
                if let source = workflow.sourceType, workflow.catalog?.clip(type: source) == nil {
                    Text("Unsupported: \(source)").tag(Array(source.utf8)).disabled(true)
                }
                ForEach(Array(workflow.typeChoices.enumerated()), id: \.offset) { _, clip in
                    Text("\(clip.type) · \(clip.rig)").tag(Array(clip.type.utf8))
                }
            }
            .pickerStyle(.menu).accessibilityLabel("Stored animation type")
            .help(workflow.selectedClip?.type ?? workflow.sourceType ?? "Choose a declared animation type")
            if let clip = workflow.selectedClip {
                Text("Declared rig: \(clip.rig)\(clip.isLegacyAlias ? " · Legacy type" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func numericField(
        name: String, label: String, defaultText: String, supported: @escaping (String) -> Bool
    ) -> some View {
        let setText = workflow.parameterAction { workflow, value in
            workflow.setText(name: name, value: value)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TextField(
                    "Default \(defaultText)",
                    text: Binding(
                        get: { workflow.parameterValue(for: name) ?? "" },
                        set: { setText($0) })
                )
                .textFieldStyle(.roundedBorder).monospacedDigit().frame(minHeight: 40)
                .focusedValue(\.editorTextEditing, true).accessibilityLabel(label)
                Button {
                    setText(nil)
                } label: {
                    Text("Default").frame(minWidth: 40, minHeight: 40)
                }.buttonStyle(.borderless)
                    .accessibilityLabel("Use default \(label)")
                    .disabled(workflow.parameterValue(for: name) == nil)
                    .help("Remove this stored override")
            }
            if let raw = workflow.parameterValue(for: name), !supported(raw) {
                Text("Unsupported value retained. Enter a replacement or use Default.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func sliderPosition(_ control: AnimationControlDefinition) -> Double? {
        guard let text = workflow.parameterDraft?.value(for: control.name) else { return Double(control.defaultSlider) }
        guard let number = Double(text), let index = try? control.slider(for: number) else { return nil }
        return Double(index)
    }
    private func surfacePicker(_ materials: [String]) -> some View {
        let raw = workflow.parameterValue(for: "surfaceMaterial")
        let setMaterial = workflow.parameterAction { workflow, material in
            workflow.setText(name: "surfaceMaterial", value: material)
        }
        return Picker(
            "Surface material",
            selection: Binding<[UInt8]?>(
                get: { workflow.parameterValue(for: "surfaceMaterial").map { Array($0.utf8) } },
                set: { value in
                    guard let value else {
                        setMaterial(nil)
                        return
                    }
                    guard let selected = materials.first(where: { $0.utf8.elementsEqual(value) }) else {
                        return
                    }
                    setMaterial(selected)
                })
        ) {
            Text("Default").tag(Optional<[UInt8]>.none)
            if let raw, !materials.contains(where: { $0.utf8.elementsEqual(raw.utf8) }) {
                Text("Unsupported: \(raw)").tag(Optional(Array(raw.utf8))).disabled(true)
            }
            ForEach(materials.indices, id: \.self) { index in
                let name = materials[index]
                Text(name).tag(Optional(Array(name.utf8)))
            }
        }
        .pickerStyle(.menu).accessibilityLabel("Stored animation surface material")
        .help("Stored surface for procedural audio; sound playback is unavailable")
    }
    private var applyTitle: String {
        switch workflow.mode {
        case .idle, .parameters: "Apply Changes"
        case .create: "Create"
        case .type: "Apply Type"
        }
    }
}
