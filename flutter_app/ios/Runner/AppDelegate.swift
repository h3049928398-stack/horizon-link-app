import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var documents: LocalDocuments?
  private var liquidGlass: LiquidGlassBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HorizonLocalDocuments") {
      documents = LocalDocuments(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HorizonLiquidGlass") {
      liquidGlass = LiquidGlassBridge(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HorizonDashboardDisplay") {
      FlutterMethodChannel(name: "horizon_link/dashboard_display", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "setAwake" else { result(FlutterMethodNotImplemented); return }
          guard let awake = call.arguments as? Bool else {
            result(FlutterError(code: "ARGUMENT", message: "Expected a Boolean", details: nil))
            return
          }
          UIApplication.shared.isIdleTimerDisabled = awake
          result(nil)
        }
    }
  }
}

// Uses the same channel/result contract as Android. Only Dart validates and
// commits imported version 2 data, after the user's existing confirmation.
final class LocalDocuments: NSObject, UIDocumentPickerDelegate {
  static let byteLimit = 64 * 1024 * 1024
  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?
  private var exported: Data?
  private var temporaryDirectory: URL?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "horizon_link/documents", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      self.handle(call, result: result)
    }
  }

  static func readBounded(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while let chunk = try handle.read(upToCount: min(1024 * 1024, byteLimit + 1 - data.count)),
      !chunk.isEmpty {
      data.append(chunk)
      if data.count > byteLimit { throw DocumentError.tooLarge }
    }
    return data
  }

  enum DocumentError: Error { case tooLarge, encoding, verification }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "version" {
      let info = Bundle.main.infoDictionary ?? [:]
      result("\(info["CFBundleShortVersionString"] as? String ?? "—")+\(info["CFBundleVersion"] as? String ?? "—")")
      return
    }
    guard call.method == "export" || call.method == "import" else {
      result(FlutterMethodNotImplemented); return
    }
    guard pending == nil else {
      result(FlutterError(code: "BUSY", message: "A document operation is already open", details: nil))
      return
    }
    // The app uses a single scene; never present into an unrelated/inactive window.
    guard let scene = UIApplication.shared.connectedScenes.first(where: {
      $0.activationState == .foregroundActive
    }) as? UIWindowScene,
      var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "PICKER", message: "No active app window", details: nil)); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    do {
      let picker: UIDocumentPickerViewController
      if call.method == "export" {
        guard let arguments = call.arguments as? [String: Any],
          let text = arguments["text"] as? String else { throw DocumentError.encoding }
        let data = Data(text.utf8)
        guard data.count <= Self.byteLimit else { throw DocumentError.tooLarge }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        temporaryDirectory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Horizon-Link-backup.json")
        try data.write(to: url, options: .atomic)
        exported = data
        picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .text, .data], asCopy: false)
      }
      pending = result
      picker.delegate = self
      picker.allowsMultipleSelection = false
      // A sheet cannot be swiped away without completing our pending callback.
      picker.isModalInPresentation = true
      presenter.present(picker, animated: true)
    } catch {
      cleanUp()
      result(FlutterError(code: "DOCUMENT", message: "Could not prepare backup file", details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(nil); return }
    let expected = exported
    // File providers (including iCloud) may block; coordinate and read off the UI thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      var coordinationError: NSError?
      var readResult: Result<Data, Error>?
      NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
        readResult = Result { try Self.readBounded(readable) }
      }
      do {
        if let error = coordinationError { throw error }
        guard let readResult = readResult else { throw DocumentError.verification }
        let data = try readResult.get()
        let answer: Any
        if let expected = expected {
          guard data == expected else { throw DocumentError.verification }
          answer = true
        } else {
          guard let text = String(data: data, encoding: .utf8) else { throw DocumentError.encoding }
          answer = text
        }
        DispatchQueue.main.async { self.finish(answer) }
      } catch {
        DispatchQueue.main.async {
          self.finish(FlutterError(code: "DOCUMENT", message: "Backup read or verification failed", details: nil))
        }
      }
    }
  }

  private func finish(_ answer: Any?) {
    let callback = pending
    pending = nil
    cleanUp()
    callback?(answer)
  }

  private func cleanUp() {
    if let directory = temporaryDirectory { try? FileManager.default.removeItem(at: directory) }
    temporaryDirectory = nil
    exported = nil
  }
}
