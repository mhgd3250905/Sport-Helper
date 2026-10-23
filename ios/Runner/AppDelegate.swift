import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentPickerDelegate {
  private var logExportChannel: FlutterMethodChannel?
  private var logExportResult: FlutterResult?
  private var logExportDirectory: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "smartfit/runtime_log_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    logExportChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "export_unavailable", message: "File save unavailable.", details: nil))
        return
      }
      guard call.method == "save" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.saveRuntimeLog(call.arguments, result: result)
    }
  }

  private func saveRuntimeLog(_ arguments: Any?, result: @escaping FlutterResult) {
    guard logExportResult == nil else {
      result(FlutterError(code: "export_busy", message: "A file save is in progress.", details: nil))
      return
    }
    guard let arguments = arguments as? [String: Any],
      let filename = arguments["filename"] as? String,
      let contents = arguments["contents"] as? String,
      filename.count <= 96,
      filename.range(of: #"^SmartFit-runtime-[A-Za-z0-9_-]+\.json$"#, options: .regularExpression) != nil,
      let data = contents.data(using: .utf8), data.count <= 4 * 1024 * 1024
    else {
      result(FlutterError(code: "invalid_export", message: "Invalid log file.", details: nil))
      return
    }
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var presenter = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "export_unavailable", message: "File save unavailable.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    logExportResult = result
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SmartFit-log-export-\(UUID().uuidString)", isDirectory: true)
    logExportDirectory = directory
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent(filename)
      try data.write(to: file, options: .atomic)
      let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      picker.delegate = self
      presenter.present(picker, animated: true)
    } catch {
      finishLogExport(error: FlutterError(
        code: "export_write_failed", message: "The log file could not be saved.", details: nil
      ))
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishLogExport(saved: !urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishLogExport(saved: false)
  }

  private func finishLogExport(saved: Bool = false, error: FlutterError? = nil) {
    let result = logExportResult
    logExportResult = nil
    if let directory = logExportDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    logExportDirectory = nil
    if let error { result?(error) } else { result?(saved) }
  }
}
