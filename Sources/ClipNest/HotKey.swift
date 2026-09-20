import AppKit
import Carbon

extension Notification.Name {
  static let showNewSnippet = Notification.Name("showNewSnippet")
  static let showQuickPicker = Notification.Name("showQuickPicker")
  static let showSnippetPicker = Notification.Name("showSnippetPicker")
  static let showTextActions = Notification.Name("showTextActions")
  static let cycleTextActionSource = Notification.Name("cycleTextActionSource")
  static let moveQuickPanelSelection = Notification.Name("moveQuickPanelSelection")
  static let useQuickPanelExtractedValue = Notification.Name("useQuickPanelExtractedValue")
  static let previewQuickPanelSelection = Notification.Name("previewQuickPanelSelection")
  static let dismissQuickPicker = Notification.Name("dismissQuickPicker")
  static let pasteBackFailed = Notification.Name("pasteBackFailed")
  static let showWelcome = Notification.Name("showWelcome")
  static let privacySessionDidSuspend = Notification.Name("privacySessionDidSuspend")
}

enum HotKeyPreset: String, CaseIterable, Identifiable, Sendable {
  case controlShiftV
  case optionSpace
  case controlOptionV
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlShiftV: "Control + Shift + V"
    case .optionSpace: "Option + Space"
    case .controlOptionV: "Control + Option + V"
    case .disabled: "Off"
    }
  }

  var display: String {
    switch self {
    case .controlShiftV: "⌃⇧V"
    case .optionSpace: "⌥Space"
    case .controlOptionV: "⌃⌥V"
    case .disabled: "Off"
    }
  }

  fileprivate var keyCode: UInt32? {
    switch self {
    case .controlShiftV, .controlOptionV: UInt32(kVK_ANSI_V)
    case .optionSpace: UInt32(kVK_Space)
    case .disabled: nil
    }
  }

  fileprivate var modifiers: UInt32 {
    switch self {
    case .controlShiftV: UInt32(controlKey | shiftKey)
    case .optionSpace: UInt32(optionKey)
    case .controlOptionV: UInt32(controlKey | optionKey)
    case .disabled: 0
    }
  }
}

enum ScreenOCRHotKeyPreset: String, CaseIterable, Identifiable, Sendable {
  case controlShiftO
  case controlOptionO
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlShiftO: "Control + Shift + O"
    case .controlOptionO: "Control + Option + O"
    case .disabled: "Off"
    }
  }

  var display: String {
    switch self {
    case .controlShiftO: "⌃⇧O"
    case .controlOptionO: "⌃⌥O"
    case .disabled: "Off"
    }
  }

  fileprivate var keyCode: UInt32? {
    self == .disabled ? nil : UInt32(kVK_ANSI_O)
  }

  fileprivate var modifiers: UInt32 {
    switch self {
    case .controlShiftO: UInt32(controlKey | shiftKey)
    case .controlOptionO: UInt32(controlKey | optionKey)
    case .disabled: 0
    }
  }
}

enum SnippetHotKeyPreset: String, CaseIterable, Identifiable, Sendable {
  case controlShiftB
  case controlOptionB
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlShiftB: "Control + Shift + B"
    case .controlOptionB: "Control + Option + B"
    case .disabled: "Off"
    }
  }

  var display: String {
    switch self {
    case .controlShiftB: "⌃⇧B"
    case .controlOptionB: "⌃⌥B"
    case .disabled: "Off"
    }
  }

  fileprivate var keyCode: UInt32? {
    self == .disabled ? nil : UInt32(kVK_ANSI_B)
  }

  fileprivate var modifiers: UInt32 {
    switch self {
    case .controlShiftB: UInt32(controlKey | shiftKey)
    case .controlOptionB: UInt32(controlKey | optionKey)
    case .disabled: 0
    }
  }
}

enum NewSnippetHotKeyPreset: String, CaseIterable, Identifiable, Sendable {
  case controlShiftN
  case controlOptionN
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlShiftN: "Control + Shift + N"
    case .controlOptionN: "Control + Option + N"
    case .disabled: "Off"
    }
  }

  var display: String {
    switch self {
    case .controlShiftN: "⌃⇧N"
    case .controlOptionN: "⌃⌥N"
    case .disabled: "Off"
    }
  }

  fileprivate var keyCode: UInt32? {
    self == .disabled ? nil : UInt32(kVK_ANSI_N)
  }

  fileprivate var modifiers: UInt32 {
    switch self {
    case .controlShiftN: UInt32(controlKey | shiftKey)
    case .controlOptionN: UInt32(controlKey | optionKey)
    case .disabled: 0
    }
  }
}

enum TextActionHotKeyPreset: String, CaseIterable, Identifiable, Sendable {
  case controlK
  case controlOptionK
  case disabled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .controlK: "Control + K"
    case .controlOptionK: "Control + Option + K"
    case .disabled: "Off"
    }
  }

  var display: String {
    switch self {
    case .controlK: "⌃K"
    case .controlOptionK: "⌃⌥K"
    case .disabled: "Off"
    }
  }

  fileprivate var keyCode: UInt32? {
    self == .disabled ? nil : UInt32(kVK_ANSI_K)
  }

  fileprivate var modifiers: UInt32 {
    switch self {
    case .controlK: UInt32(controlKey)
    case .controlOptionK: UInt32(controlKey | optionKey)
    case .disabled: 0
    }
  }
}

private final class HotKeyHandlerContext: @unchecked Sendable {
  let signature: OSType
  let identifier: UInt32
  let action: @MainActor @Sendable () -> Void

  init(
    signature: OSType,
    identifier: UInt32,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    self.signature = signature
    self.identifier = identifier
    self.action = action
  }
}

private final class GlobalHotKeyRegistration {
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private let context: HotKeyHandlerContext
  private(set) var registrationSucceeded = false

  init(identifier: UInt32, action: @escaping @MainActor @Sendable () -> Void) {
    let signature = OSType(UInt32(ascii: "CLPN"))
    context = HotKeyHandlerContext(
      signature: signature,
      identifier: identifier,
      action: action
    )
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let context = Unmanaged<HotKeyHandlerContext>.fromOpaque(userData).takeUnretainedValue()
        var pressedID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &pressedID
        )
        guard status == noErr,
          pressedID.signature == context.signature,
          pressedID.id == context.identifier
        else { return OSStatus(eventNotHandledErr) }
        Task { @MainActor in context.action() }
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(context).toOpaque(),
      &handlerRef
    )
  }

  @discardableResult
  func update(keyCode: UInt32?, modifiers: UInt32) -> Bool {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
    guard let keyCode else {
      registrationSucceeded = true
      return true
    }
    guard handlerRef != nil else {
      registrationSucceeded = false
      return false
    }
    let id = EventHotKeyID(signature: context.signature, id: context.identifier)
    let status = RegisterEventHotKey(
      keyCode,
      modifiers,
      id,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    if status != noErr { hotKeyRef = nil }
    registrationSucceeded = status == noErr
    return registrationSucceeded
  }

  deinit {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    if let handlerRef { RemoveEventHandler(handlerRef) }
  }
}

final class GlobalHotKey {
  private let registration: GlobalHotKeyRegistration
  var registrationSucceeded: Bool { registration.registrationSucceeded }

  init(preset: HotKeyPreset) {
    registration = GlobalHotKeyRegistration(identifier: 1) {
      NotificationCenter.default.post(name: .showQuickPicker, object: nil)
    }
    update(to: preset)
  }

  @discardableResult
  func update(to preset: HotKeyPreset) -> Bool {
    registration.update(keyCode: preset.keyCode, modifiers: preset.modifiers)
  }
}

final class ScreenOCRGlobalHotKey {
  private let registration: GlobalHotKeyRegistration
  var registrationSucceeded: Bool { registration.registrationSucceeded }

  init(
    preset: ScreenOCRHotKeyPreset,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    registration = GlobalHotKeyRegistration(identifier: 2, action: action)
    update(to: preset)
  }

  @discardableResult
  func update(to preset: ScreenOCRHotKeyPreset) -> Bool {
    registration.update(keyCode: preset.keyCode, modifiers: preset.modifiers)
  }
}

final class SnippetGlobalHotKey {
  private let registration: GlobalHotKeyRegistration
  var registrationSucceeded: Bool { registration.registrationSucceeded }

  init(
    preset: SnippetHotKeyPreset,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    registration = GlobalHotKeyRegistration(identifier: 3, action: action)
    update(to: preset)
  }

  @discardableResult
  func update(to preset: SnippetHotKeyPreset) -> Bool {
    registration.update(keyCode: preset.keyCode, modifiers: preset.modifiers)
  }
}

final class TextActionGlobalHotKey {
  private let registration: GlobalHotKeyRegistration
  var registrationSucceeded: Bool { registration.registrationSucceeded }

  init(
    preset: TextActionHotKeyPreset,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    registration = GlobalHotKeyRegistration(identifier: 4, action: action)
    update(to: preset)
  }

  @discardableResult
  func update(to preset: TextActionHotKeyPreset) -> Bool {
    registration.update(keyCode: preset.keyCode, modifiers: preset.modifiers)
  }
}

final class NewSnippetGlobalHotKey {
  private let registration: GlobalHotKeyRegistration
  var registrationSucceeded: Bool { registration.registrationSucceeded }

  init(
    preset: NewSnippetHotKeyPreset,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    registration = GlobalHotKeyRegistration(identifier: 5, action: action)
    update(to: preset)
  }

  @discardableResult
  func update(to preset: NewSnippetHotKeyPreset) -> Bool {
    registration.update(keyCode: preset.keyCode, modifiers: preset.modifiers)
  }
}

extension UInt32 {
  fileprivate init(ascii: String) {
    self = ascii.utf8.prefix(4).reduce(0) { ($0 << 8) + UInt32($1) }
  }
}
