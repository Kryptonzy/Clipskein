import SwiftUI

struct BoardEditorView: View {
  let title: String
  let initialName: String
  let onSave: (String) -> Bool
  let onCancel: () -> Void

  @State private var name: String
  @FocusState private var focused: Bool

  init(
    title: String,
    initialName: String = "",
    onSave: @escaping (String) -> Bool,
    onCancel: @escaping () -> Void
  ) {
    self.title = title
    self.initialName = initialName
    self.onSave = onSave
    self.onCancel = onCancel
    _name = State(initialValue: initialName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 20, weight: .bold, design: .rounded))
        Text(
          L10n.text(
            "board_editor.detail",
            fallback: "Pinboards keep reusable clips together without changing their tags.")
        )
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      }

      TextField(L10n.text("board_editor.placeholder", fallback: "Pinboard name"), text: $name)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onSubmit(save)

      HStack {
        Spacer()
        Button(L10n.text("board_editor.cancel", fallback: "Cancel"), action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(
          initialName.isEmpty
            ? L10n.text("board_editor.create", fallback: "Create")
            : L10n.text("board_editor.save", fallback: "Save"),
          action: save
        )
        .keyboardShortcut(.defaultAction)
        .disabled(normalizedName.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 390)
    .onAppear { focused = true }
  }

  private var normalizedName: String {
    ClipStore.normalizedBoardName(name)
  }

  private func save() {
    guard !normalizedName.isEmpty else { return }
    _ = onSave(normalizedName)
  }
}
