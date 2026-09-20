import SwiftUI

struct SaveViewSheet: View {
  let suggestedName: String
  let criteriaDescription: String
  let onSave: (String) -> Bool
  let onCancel: () -> Void

  @State private var name: String
  @State private var failureMessage: String?
  @FocusState private var nameIsFocused: Bool

  init(
    suggestedName: String,
    criteriaDescription: String,
    onSave: @escaping (String) -> Bool,
    onCancel: @escaping () -> Void
  ) {
    self.suggestedName = suggestedName
    self.criteriaDescription = criteriaDescription
    self.onSave = onSave
    self.onCancel = onCancel
    _name = State(initialValue: suggestedName)
  }

  private var normalizedName: String {
    ClipStore.normalizedSavedViewName(name)
  }

  private var isTooLong: Bool {
    name.count > SavedClipView.maximumNameLength
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.text("save_view.title", fallback: "Save this view"))
          .font(.system(size: 22, weight: .bold, design: .rounded))
        Text(
          L10n.text(
            "save_view.detail",
            fallback: "Return to this exact search and filter combination in one click.")
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        TextField(
          L10n.text("save_view.placeholder", fallback: "Example: Recent work links"),
          text: $name
        )
        .textFieldStyle(.roundedBorder)
        .focused($nameIsFocused)
        .onSubmit(save)
        HStack {
          if isTooLong {
            Text(
              L10n.format(
                "save_view.name_limit",
                fallback: "Keep the name under %d characters.",
                SavedClipView.maximumNameLength)
            )
            .foregroundStyle(.red)
          }
          Spacer()
          Text("\(name.count)/\(SavedClipView.maximumNameLength)")
            .monospacedDigit()
            .foregroundStyle(isTooLong ? .red : .secondary)
        }
        .font(.system(size: 11, weight: .medium))
      }

      Label(criteriaDescription, systemImage: "line.3.horizontal.decrease.circle")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(3)

      if let failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.orange)
      }

      HStack {
        Spacer()
        Button(L10n.text("save_view.cancel", fallback: "Cancel"), action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.text("save_view.save", fallback: "Save view"), action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(normalizedName.isEmpty || isTooLong)
      }
    }
    .padding(24)
    .frame(width: 440)
    .onAppear { nameIsFocused = true }
  }

  private func save() {
    guard !normalizedName.isEmpty, !isTooLong else { return }
    if !onSave(normalizedName) {
      failureMessage = L10n.text(
        "save_view.limit_recovery", fallback: "Remove an existing saved view, then try again.")
    }
  }
}
