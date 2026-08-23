import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
  private enum Keys {
    static let gainDB = "gainDB"
    static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
    static let customMappingEnabled = "customMappingEnabled"
    static let legacyExclusiveHID = "exclusiveHID"
    static let buttonBindings = "buttonBindings"
    static let buttonShortcuts = "buttonShortcuts"
    static let buttonApplicationProfileIDs = "buttonApplicationProfileIDs"
    static let secondaryButtonBindings = "secondaryButtonBindings"
    static let customApplicationProfiles = "customApplicationProfiles"
    static let peripheralIdentifier = "peripheralIdentifier"
    static let remoteDeviceProfiles = "remoteDeviceProfiles"
    static let selectedRemoteProfileID = "selectedRemoteProfileID"
    static let applicationLanguage = "applicationLanguage"
    static let voiceFnTapModeEnabled = "voiceFnTapModeEnabled"
    static let setupHasPresented = "setup.hasPresented"
    static let setupCompleted = "setup.completed"
    static let legacyOnboardingCompletedVersion = "onboarding.completedVersion"
  }

  static let defaultBindings: [RemoteButton: ButtonAction] = [
    .power: .escape,
    .up: .arrowUp,
    .left: .arrowLeft,
    .ok: .returnKey,
    .right: .arrowRight,
    .down: .arrowDown,
    .back: .deleteBackward,
    .volumeUp: .volumeUp,
    .home: .showDesktop,
    .volumeDown: .volumeDown,
    .menu: .contextMenu,
    .tv: .appSwitcher,
  ]

  private let defaults: UserDefaults
  private var isLoadingRemoteProfile = false

  var gainDB: Double {
    didSet { defaults.set(gainDB, forKey: Keys.gainDB) }
  }

  var selectedAudioDeviceUID: String {
    didSet { defaults.set(selectedAudioDeviceUID, forKey: Keys.selectedAudioDeviceUID) }
  }

  var customMappingEnabled: Bool {
    didSet { defaults.set(customMappingEnabled, forKey: Keys.customMappingEnabled) }
  }

  var buttonBindings: [RemoteButton: ButtonAction] {
    didSet {
      save(buttonBindings, key: Keys.buttonBindings)
      saveSelectedRemoteProfileMappings()
    }
  }

  var buttonShortcuts: [RemoteButton: CustomKeyboardShortcut] {
    didSet {
      save(buttonShortcuts, key: Keys.buttonShortcuts)
      saveSelectedRemoteProfileMappings()
    }
  }

  var buttonApplicationProfileIDs: [RemoteButton: UUID] {
    didSet {
      save(buttonApplicationProfileIDs, key: Keys.buttonApplicationProfileIDs)
      saveSelectedRemoteProfileMappings()
    }
  }

  var secondaryButtonBindings: [RemoteButton: [ButtonTrigger: ConfiguredButtonAction]] {
    didSet {
      saveSecondaryBindings()
      saveSelectedRemoteProfileMappings()
    }
  }

  private(set) var customApplicationProfiles: [CustomApplicationProfile] {
    didSet { saveCodable(customApplicationProfiles, key: Keys.customApplicationProfiles) }
  }

  private(set) var remoteDeviceProfiles: [RemoteDeviceProfile] {
    didSet { saveCodable(remoteDeviceProfiles, key: Keys.remoteDeviceProfiles) }
  }

  private(set) var selectedRemoteProfileID: UUID? {
    didSet {
      defaults.set(selectedRemoteProfileID?.uuidString, forKey: Keys.selectedRemoteProfileID)
    }
  }

  var applicationLanguage: AppLanguage {
    didSet { defaults.set(applicationLanguage.rawValue, forKey: Keys.applicationLanguage) }
  }

  var voiceFnTapModeEnabled: Bool {
    didSet { defaults.set(voiceFnTapModeEnabled, forKey: Keys.voiceFnTapModeEnabled) }
  }

  private(set) var setupHasPresented: Bool {
    didSet { defaults.set(setupHasPresented, forKey: Keys.setupHasPresented) }
  }

  private(set) var setupCompleted: Bool {
    didSet { defaults.set(setupCompleted, forKey: Keys.setupCompleted) }
  }

  var peripheralIdentifier: UUID? {
    get {
      defaults.string(forKey: Keys.peripheralIdentifier).flatMap(UUID.init(uuidString:))
    }
    set {
      defaults.set(newValue?.uuidString, forKey: Keys.peripheralIdentifier)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    remoteDeviceProfiles = []
    selectedRemoteProfileID = nil
    gainDB =
      defaults.object(forKey: Keys.gainDB) == nil
      ? 10
      : defaults.double(forKey: Keys.gainDB)
    selectedAudioDeviceUID = defaults.string(forKey: Keys.selectedAudioDeviceUID) ?? ""
    if defaults.object(forKey: Keys.customMappingEnabled) != nil {
      customMappingEnabled = defaults.bool(forKey: Keys.customMappingEnabled)
    } else if defaults.object(forKey: Keys.legacyExclusiveHID) != nil {
      customMappingEnabled = defaults.bool(forKey: Keys.legacyExclusiveHID)
    } else {
      customMappingEnabled = true
    }

    let savedBindings: [RemoteButton: ButtonAction] = Self.decodeKeyed(
      defaults.data(forKey: Keys.buttonBindings)
    )
    buttonBindings = Self.defaultBindings.merging(savedBindings) { _, saved in saved }
    buttonShortcuts = Self.decodeKeyed(defaults.data(forKey: Keys.buttonShortcuts))
    buttonApplicationProfileIDs = Self.decodeKeyed(
      defaults.data(forKey: Keys.buttonApplicationProfileIDs)
    )
    secondaryButtonBindings = Self.decodeSecondary(
      defaults.data(forKey: Keys.secondaryButtonBindings)
    )
    customApplicationProfiles =
      Self.decode(
        [CustomApplicationProfile].self,
        from: defaults.data(forKey: Keys.customApplicationProfiles)
      ) ?? []
    applicationLanguage =
      AppLanguage(
        rawValue: defaults.string(forKey: Keys.applicationLanguage) ?? ""
      ) ?? .system
    voiceFnTapModeEnabled = defaults.bool(forKey: Keys.voiceFnTapModeEnabled)

    let hasNewSetupState =
      defaults.object(forKey: Keys.setupHasPresented) != nil
      || defaults.object(forKey: Keys.setupCompleted) != nil
    let legacySetupCompleted = defaults.integer(forKey: Keys.legacyOnboardingCompletedVersion) > 0
    setupHasPresented =
      hasNewSetupState
      ? defaults.bool(forKey: Keys.setupHasPresented)
      : legacySetupCompleted
    setupCompleted =
      hasNewSetupState
      ? defaults.bool(forKey: Keys.setupCompleted)
      : legacySetupCompleted

    let legacyMappings = RemoteDeviceMappings(
      buttonBindings: buttonBindings,
      buttonShortcuts: buttonShortcuts,
      buttonApplicationProfileIDs: buttonApplicationProfileIDs,
      secondaryButtonBindings: secondaryButtonBindings
    )
    let decodedProfiles =
      Self.decode(
        [RemoteDeviceProfile].self,
        from: defaults.data(forKey: Keys.remoteDeviceProfiles)
      ) ?? []
    if decodedProfiles.isEmpty {
      let migrated = RemoteDeviceProfile(
        bluetoothIdentifier: defaults.string(forKey: Keys.peripheralIdentifier)
          .flatMap(UUID.init(uuidString:)),
        mappings: legacyMappings
      )
      remoteDeviceProfiles = [migrated]
      selectedRemoteProfileID = migrated.id
    } else {
      remoteDeviceProfiles = decodedProfiles
      let savedID = defaults.string(forKey: Keys.selectedRemoteProfileID)
        .flatMap(UUID.init(uuidString:))
      selectedRemoteProfileID =
        decodedProfiles.contains(where: { $0.id == savedID })
        ? savedID
        : decodedProfiles[0].id
      if let selectedRemoteProfileID,
        let selected = decodedProfiles.first(where: { $0.id == selectedRemoteProfileID })
      {
        buttonBindings = Self.defaultBindings.merging(
          selected.mappings.parsedButtonBindings
        ) { _, saved in saved }
        buttonShortcuts = selected.mappings.parsedButtonShortcuts
        buttonApplicationProfileIDs = selected.mappings.parsedButtonApplicationProfileIDs
        secondaryButtonBindings = selected.mappings.parsedSecondaryButtonBindings
      }
    }
  }

  func markSetupPresented() {
    setupHasPresented = true
  }

  func completeSetup() {
    setupHasPresented = true
    setupCompleted = true
  }

  func action(for button: RemoteButton) -> ButtonAction {
    buttonBindings[button] ?? .disabled
  }

  func action(for button: RemoteButton, profileID: UUID?) -> ButtonAction {
    guard let profileID, profileID != selectedRemoteProfileID,
      let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
    else { return action(for: button) }
    return profile.mappings.parsedButtonBindings[button]
      ?? Self.defaultBindings[button]
      ?? .disabled
  }

  func setAction(_ action: ButtonAction, for button: RemoteButton) {
    buttonBindings[button] = action
  }

  func shortcut(for button: RemoteButton) -> CustomKeyboardShortcut? {
    buttonShortcuts[button]
  }

  func shortcut(for button: RemoteButton, profileID: UUID?) -> CustomKeyboardShortcut? {
    guard let profileID, profileID != selectedRemoteProfileID,
      let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
    else { return shortcut(for: button) }
    return profile.mappings.parsedButtonShortcuts[button]
  }

  func setShortcut(_ shortcut: CustomKeyboardShortcut?, for button: RemoteButton) {
    buttonShortcuts[button] = shortcut
  }

  func applicationProfileID(for button: RemoteButton) -> UUID? {
    buttonApplicationProfileIDs[button]
  }

  func applicationProfileID(for button: RemoteButton, profileID: UUID?) -> UUID? {
    guard let profileID, profileID != selectedRemoteProfileID,
      let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
    else { return applicationProfileID(for: button) }
    return profile.mappings.parsedButtonApplicationProfileIDs[button]
  }

  func customApplicationProfile(id: UUID?) -> CustomApplicationProfile? {
    guard let id else { return nil }
    return customApplicationProfiles.first(where: { $0.id == id })
  }

  @discardableResult
  func addCustomApplicationProfile(_ profile: CustomApplicationProfile) -> UUID {
    customApplicationProfiles.append(profile)
    return profile.id
  }

  func updateCustomApplicationProfile(_ profile: CustomApplicationProfile) {
    guard let index = customApplicationProfiles.firstIndex(where: { $0.id == profile.id }) else {
      return
    }
    customApplicationProfiles[index] = profile
  }

  func removeCustomApplicationProfile(_ profileID: UUID) {
    customApplicationProfiles.removeAll(where: { $0.id == profileID })
    for button in RemoteButton.allCases where buttonApplicationProfileIDs[button] == profileID {
      buttonApplicationProfileIDs[button] = nil
    }
    for button in RemoteButton.allCases {
      var bindings = secondaryButtonBindings[button] ?? [:]
      for trigger in ButtonTrigger.allCases
      where bindings[trigger]?.applicationProfileID == profileID {
        bindings[trigger]?.applicationProfileID = nil
      }
      secondaryButtonBindings[button] = bindings.isEmpty ? nil : bindings
    }
  }

  func configuredAction(
    for button: RemoteButton,
    trigger: ButtonTrigger
  ) -> ConfiguredButtonAction {
    configuredAction(for: button, trigger: trigger, profileID: selectedRemoteProfileID)
  }

  func configuredAction(
    for button: RemoteButton,
    trigger: ButtonTrigger,
    profileID: UUID?
  ) -> ConfiguredButtonAction {
    let isSelected = profileID == nil || profileID == selectedRemoteProfileID
    if trigger == .singleClick {
      return ConfiguredButtonAction(
        action: action(for: button, profileID: profileID),
        shortcut: shortcut(for: button, profileID: profileID),
        applicationProfileID: applicationProfileID(for: button, profileID: profileID)
      )
    }
    if isSelected {
      return secondaryButtonBindings[button]?[trigger] ?? .disabled
    }
    guard let profileID,
      let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
    else { return .disabled }
    return profile.mappings.parsedSecondaryButtonBindings[button]?[trigger] ?? .disabled
  }

  var selectedRemoteProfile: RemoteDeviceProfile? {
    guard let selectedRemoteProfileID else { return nil }
    return remoteDeviceProfiles.first(where: { $0.id == selectedRemoteProfileID })
  }

  func selectRemoteProfile(_ profileID: UUID) {
    guard profileID != selectedRemoteProfileID,
      let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
    else { return }
    isLoadingRemoteProfile = true
    selectedRemoteProfileID = profileID
    buttonBindings = Self.defaultBindings.merging(profile.mappings.parsedButtonBindings) {
      _, saved in saved
    }
    buttonShortcuts = profile.mappings.parsedButtonShortcuts
    buttonApplicationProfileIDs = profile.mappings.parsedButtonApplicationProfileIDs
    secondaryButtonBindings = profile.mappings.parsedSecondaryButtonBindings
    isLoadingRemoteProfile = false
  }

  @discardableResult
  func registerBluetoothRemote(identifier: UUID) -> UUID {
    if let profile = remoteDeviceProfiles.first(where: { $0.bluetoothIdentifier == identifier }) {
      return profile.id
    }
    if let index = remoteDeviceProfiles.firstIndex(where: {
      $0.bluetoothIdentifier == nil && $0.model == .unknown
    }) {
      remoteDeviceProfiles[index].bluetoothIdentifier = identifier
      return remoteDeviceProfiles[index].id
    }
    let profile = RemoteDeviceProfile(
      bluetoothIdentifier: identifier,
      mappings: mappingsForNewRemote()
    )
    remoteDeviceProfiles.append(profile)
    return profile.id
  }

  @discardableResult
  func registerHIDRemote(fingerprint: String) -> UUID {
    if let profile = remoteDeviceProfiles.first(where: { $0.hidFingerprint == fingerprint }) {
      return profile.id
    }
    if let index = remoteDeviceProfiles.firstIndex(where: {
      $0.id == selectedRemoteProfileID && $0.hidFingerprint == nil
    }) ?? remoteDeviceProfiles.firstIndex(where: { $0.hidFingerprint == nil }) {
      remoteDeviceProfiles[index].hidFingerprint = fingerprint
      return remoteDeviceProfiles[index].id
    }
    let profile = RemoteDeviceProfile(
      hidFingerprint: fingerprint,
      mappings: mappingsForNewRemote()
    )
    remoteDeviceProfiles.append(profile)
    return profile.id
  }

  func profileID(forBluetoothIdentifier identifier: UUID) -> UUID? {
    remoteDeviceProfiles.first(where: { $0.bluetoothIdentifier == identifier })?.id
  }

  func profileID(forHIDFingerprint fingerprint: String) -> UUID? {
    remoteDeviceProfiles.first(where: { $0.hidFingerprint == fingerprint })?.id
  }

  func bindHIDFingerprint(_ fingerprint: String, to profileID: UUID) {
    guard let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }) else {
      return
    }
    for candidate in remoteDeviceProfiles.indices
    where remoteDeviceProfiles[candidate].hidFingerprint == fingerprint {
      remoteDeviceProfiles[candidate].hidFingerprint = nil
    }
    remoteDeviceProfiles[index].hidFingerprint = fingerprint
  }

  func updateRemoteProfile(
    _ profileID: UUID,
    model: XiaomiRemoteModel,
    customName: String
  ) {
    guard let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }) else {
      return
    }
    remoteDeviceProfiles[index].model = model
    remoteDeviceProfiles[index].customName = customName.trimmingCharacters(
      in: .whitespacesAndNewlines)
  }

  func updateRemoteProfileModel(_ profileID: UUID, model: XiaomiRemoteModel) {
    guard model != .unknown,
      let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }),
      remoteDeviceProfiles[index].model != model
    else { return }
    remoteDeviceProfiles[index].model = model
  }

  func setAction(_ action: ButtonAction, for button: RemoteButton, trigger: ButtonTrigger) {
    guard trigger != .singleClick else {
      setAction(action, for: button)
      return
    }
    var bindings = secondaryButtonBindings[button] ?? [:]
    let current = bindings[trigger] ?? .disabled
    bindings[trigger] = ConfiguredButtonAction(
      action: action,
      shortcut: current.shortcut,
      applicationProfileID: current.applicationProfileID
    )
    secondaryButtonBindings[button] = bindings
  }

  func setApplicationProfileID(
    _ profileID: UUID?,
    for button: RemoteButton,
    trigger: ButtonTrigger
  ) {
    if trigger == .singleClick {
      buttonApplicationProfileIDs[button] = profileID
      return
    }
    var bindings = secondaryButtonBindings[button] ?? [:]
    var binding = bindings[trigger] ?? .disabled
    binding.applicationProfileID = profileID
    bindings[trigger] = binding
    secondaryButtonBindings[button] = bindings
  }

  func setShortcut(
    _ shortcut: CustomKeyboardShortcut?,
    for button: RemoteButton,
    trigger: ButtonTrigger
  ) {
    if trigger == .singleClick {
      setShortcut(shortcut, for: button)
      return
    }
    var bindings = secondaryButtonBindings[button] ?? [:]
    var binding = bindings[trigger] ?? .disabled
    binding.shortcut = shortcut
    bindings[trigger] = binding
    secondaryButtonBindings[button] = bindings
  }

  func hasSecondaryAction(for button: RemoteButton, profileID: UUID? = nil) -> Bool {
    [ButtonTrigger.doubleClick, .longPress].contains { trigger in
      configuredAction(
        for: button,
        trigger: trigger,
        profileID: profileID ?? selectedRemoteProfileID
      ).action != .disabled
    }
  }

  func resetBindings() {
    buttonBindings = Self.defaultBindings
    buttonShortcuts = [:]
    buttonApplicationProfileIDs = [:]
    secondaryButtonBindings = [:]
  }

  private func mappingsForNewRemote() -> RemoteDeviceMappings {
    selectedRemoteProfile?.mappings
      ?? RemoteDeviceMappings(
        buttonBindings: buttonBindings,
        buttonShortcuts: buttonShortcuts,
        buttonApplicationProfileIDs: buttonApplicationProfileIDs,
        secondaryButtonBindings: secondaryButtonBindings
      )
  }

  private func saveSelectedRemoteProfileMappings() {
    guard !isLoadingRemoteProfile,
      let selectedRemoteProfileID,
      let index = remoteDeviceProfiles.firstIndex(where: { $0.id == selectedRemoteProfileID })
    else { return }
    remoteDeviceProfiles[index].mappings = RemoteDeviceMappings(
      buttonBindings: buttonBindings,
      buttonShortcuts: buttonShortcuts,
      buttonApplicationProfileIDs: buttonApplicationProfileIDs,
      secondaryButtonBindings: secondaryButtonBindings
    )
  }

  private func save<Value: Codable>(_ values: [RemoteButton: Value], key: String) {
    let raw = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    saveCodable(raw, key: key)
  }

  private func saveSecondaryBindings() {
    let raw = Dictionary(
      uniqueKeysWithValues: secondaryButtonBindings.map { button, bindings in
        (
          button.rawValue,
          Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        )
      })
    saveCodable(raw, key: Keys.secondaryButtonBindings)
  }

  private func saveCodable<T: Encodable>(_ value: T, key: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: key)
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
    data.flatMap { try? JSONDecoder().decode(type, from: $0) }
  }

  private static func decodeKeyed<Value: Codable>(_ data: Data?) -> [RemoteButton: Value] {
    let raw = decode([String: Value].self, from: data) ?? [:]
    return Dictionary(
      uniqueKeysWithValues: raw.compactMap { key, value in
        RemoteButton(rawValue: key).map { ($0, value) }
      })
  }

  private static func decodeSecondary(
    _ data: Data?
  ) -> [RemoteButton: [ButtonTrigger: ConfiguredButtonAction]] {
    let raw = decode([String: [String: ConfiguredButtonAction]].self, from: data) ?? [:]
    return Dictionary(
      uniqueKeysWithValues: raw.compactMap { buttonKey, bindings in
        guard let button = RemoteButton(rawValue: buttonKey) else { return nil }
        let parsed = Dictionary(
          uniqueKeysWithValues: bindings.compactMap { triggerKey, value in
            ButtonTrigger(rawValue: triggerKey).map { ($0, value) }
          })
        return (button, parsed)
      })
  }
}
