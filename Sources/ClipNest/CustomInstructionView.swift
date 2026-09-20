import SwiftUI

struct CustomInstructionView: View {
  @ObservedObject var preferences: ClipPreferences
  let onRun: (String) -> Void
  let onCancel: () -> Void

  @State private var instruction = ""
  @State private var instructionName = ""
  @State private var saveForLater = false
  @FocusState private var instructionIsFocused: Bool

  private var trimmedInstruction: String {
    instruction.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          L10n.text("custom_instruction.title", fallback: "Custom local transformation")
        )
        .font(.system(size: 22, weight: .bold, design: .rounded))
        Text(
          L10n.text(
            "custom_instruction.detail",
            fallback: "Describe the result you want. The clip stays on this Mac.")
        )
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      }

      if !preferences.savedLocalInstructions.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(L10n.text("custom_instruction.saved", fallback: "SAVED INSTRUCTIONS"))
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(.secondary)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(preferences.savedLocalInstructions) { saved in
                HStack(spacing: 4) {
                  Button(saved.name) {
                    onRun(saved.prompt)
                  }
                  .buttonStyle(.bordered)
                  .help(saved.prompt)
                  Button {
                    preferences.deleteLocalInstruction(id: saved.id)
                  } label: {
                    Image(systemName: "xmark")
                      .font(.system(size: 9, weight: .bold))
                  }
                  .buttonStyle(.plain)
                  .help(L10n.text("custom_instruction.delete", fallback: "Delete instruction"))
                }
                .padding(.trailing, 3)
              }
            }
          }
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        TextEditor(text: $instruction)
          .font(.system(size: 14, design: .rounded))
          .focused($instructionIsFocused)
          .scrollContentBackground(.hidden)
          .padding(9)
          .frame(height: 115)
          .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))

        HStack {
          Text(
            L10n.text(
              "custom_instruction.example",
              fallback: "Example: Turn this into a friendly follow-up email.")
          )
          .foregroundStyle(.secondary)
          Spacer()
          Text("\(instruction.count)/\(LocalIntelligenceService.maximumInstructionLength)")
            .monospacedDigit()
            .foregroundStyle(
              instruction.count > LocalIntelligenceService.maximumInstructionLength
                ? .red : .secondary)
        }
        .font(.system(size: 11, weight: .medium))
      }

      Toggle(
        L10n.text("custom_instruction.save", fallback: "Save as a reusable instruction"),
        isOn: $saveForLater
      )
      if saveForLater {
        TextField(
          L10n.text("custom_instruction.name", fallback: "Instruction name"),
          text: $instructionName
        )
        .textFieldStyle(.roundedBorder)
      }

      HStack {
        Spacer()
        Button(L10n.text("custom_instruction.cancel", fallback: "Cancel"), action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button(L10n.text("custom_instruction.run", fallback: "Run on this Mac")) {
          if saveForLater {
            _ = preferences.saveLocalInstruction(name: instructionName, prompt: trimmedInstruction)
          }
          onRun(trimmedInstruction)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          trimmedInstruction.isEmpty
            || instruction.count > LocalIntelligenceService.maximumInstructionLength
            || (saveForLater
              && instructionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
      }
    }
    .padding(24)
    .frame(width: 540)
    .onAppear { instructionIsFocused = true }
  }
}
