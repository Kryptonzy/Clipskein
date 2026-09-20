import SwiftUI

struct TemplateFillView: View {
  let item: ClipItem
  let template: ClipTemplate
  let actionLabel: String
  let onSubmit: (String) -> Bool
  let onCancel: () -> Void

  @State private var values: [String: String]
  @State private var failureMessage: String?
  @State private var now = Date.now
  @State private var identifier = UUID()
  @FocusState private var focusedField: String?

  init(
    item: ClipItem,
    template: ClipTemplate,
    actionLabel: String,
    onSubmit: @escaping (String) -> Bool,
    onCancel: @escaping () -> Void
  ) {
    self.item = item
    self.template = template
    self.actionLabel = actionLabel
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    _values = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: template.fields.map { ($0.key, $0.defaultValue) }
      )
    )
  }

  private var renderedText: String {
    template.render(values: values, now: now, identifier: identifier)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.text("template_fill.title", fallback: "Fill template"))
          .font(.system(size: 22, weight: .bold, design: .rounded))
        Text(
          item.customTitle ?? item.alias.map { "@\($0)" }
            ?? L10n.text("template_fill.reusable_clip", fallback: "Reusable clip")
        )
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(template.fields) { field in
            VStack(alignment: .leading, spacing: 6) {
              Text(field.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
              TextField(
                field.defaultValue.isEmpty
                  ? L10n.format(
                    "template_fill.field_placeholder",
                    fallback: "Enter %@",
                    field.label)
                  : "",
                text: binding(for: field)
              )
              .textFieldStyle(.roundedBorder)
              .focused($focusedField, equals: field.key)
            }
          }

          VStack(alignment: .leading, spacing: 7) {
            HStack {
              Text(L10n.text("template_fill.preview", fallback: "PREVIEW"))
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(1.1)
              Spacer()
              Text(
                L10n.text(
                  "template_fill.dynamic_dates",
                  fallback: "Live date, offset, ISO 8601, and UUID values refresh together")
              )
              .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)

            Text(renderedText)
              .font(.system(size: 13, design: .rounded))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(12)
              .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
              .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.16)))
          }
        }
      }

      if let failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.orange)
      }

      HStack {
        Button {
          now = .now
          identifier = UUID()
        } label: {
          Label(
            L10n.text("template_fill.refresh", fallback: "Refresh dynamic values"),
            systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        Spacer()
        Button(L10n.text("template_fill.cancel", fallback: "Cancel"), action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(actionLabel, action: submit)
          .keyboardShortcut(.defaultAction)
          .disabled(renderedText.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 620, height: min(620, 350 + CGFloat(template.fields.count) * 55))
    .onAppear { focusedField = template.fields.first?.key }
  }

  private func binding(for field: ClipTemplateField) -> Binding<String> {
    Binding(
      get: { values[field.key, default: field.defaultValue] },
      set: {
        values[field.key] = $0
        failureMessage = nil
      }
    )
  }

  private func submit() {
    guard !renderedText.isEmpty else { return }
    if !onSubmit(renderedText) {
      failureMessage = L10n.text(
        "template_fill.copy_failed",
        fallback: "Clipskein could not copy the filled template. Your entries are still here."
      )
    }
  }
}
