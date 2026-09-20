import SwiftUI

#if canImport(Translation)
  import Translation
#endif

extension View {
  @ViewBuilder
  func localTranslationTask(controller: LocalTranslationController) -> some View {
    #if canImport(Translation)
      if #available(macOS 15.0, *) {
        modifier(
          LocalTranslationTaskModifier(
            controller: controller,
            taskState: controller.taskState()
          ))
      } else {
        self
      }
    #else
      self
    #endif
  }
}

#if canImport(Translation)
  @available(macOS 15.0, *)
  private struct LocalTranslationTaskModifier: ViewModifier {
    @ObservedObject var controller: LocalTranslationController
    @ObservedObject var taskState: LocalTranslationTaskState

    func body(content: Content) -> some View {
      content
        .translationTask(taskState.configuration) { session in
          await controller.perform(session)
        }
    }
  }
#endif
