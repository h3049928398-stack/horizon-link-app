import Flutter
import UIKit

final class LiquidGlassBridge: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  init(registrar: FlutterPluginRegistrar) {
    super.init()
    let channel = FlutterEventChannel(
      name: "horizon_link/liquid_glass", binaryMessenger: registrar.messenger()
    )
    registrar.register(LiquidGlassFactory(), withId: "horizon_link/liquid_glass_surface")
    registrar.register(GlassControlsFactory(registrar.messenger()), withId: "horizon_link/controls")
    channel.setStreamHandler(self)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  static func enabled(supportsMaterial: Bool, reduceTransparency: Bool) -> Bool {
    supportsMaterial && !reduceTransparency
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    NotificationCenter.default.removeObserver(self)
    sink = events
    NotificationCenter.default.addObserver(
      self, selector: #selector(accessibilityChanged(_:)),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(accessibilityChanged(_:)),
      name: UIApplication.didBecomeActiveNotification, object: nil
    )
    publishAvailability()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    sink = nil
    return nil
  }

  @objc private func accessibilityChanged(_ notification: NSNotification) {
    publishAvailability()
  }

  private func publishAvailability() {
    let supportsMaterial: Bool
    if #available(iOS 26.0, *) {
      supportsMaterial = true
    } else {
      supportsMaterial = false
    }
    sink?(Self.enabled(
      supportsMaterial: supportsMaterial,
      reduceTransparency: UIAccessibility.isReduceTransparencyEnabled
    ))
  }
}

private final class LiquidGlassFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let options = args as? [String: Any]
    return LiquidGlassView(
      frame: frame, dark: options?["dark"] as? Bool ?? false,
      capsule: options?["capsule"] as? Bool ?? false
    )
  }
}

private final class LiquidGlassView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, dark: Bool, capsule: Bool) {
    container = UIView(frame: frame)
    super.init()
    container.isUserInteractionEnabled = false
    container.accessibilityElementsHidden = true
    container.overrideUserInterfaceStyle = dark ? .dark : .light
    if #available(iOS 26.0, *) {
      let material = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
      material.cornerConfiguration = capsule ? .capsule() : .corners(radius: .fixed(22))
      material.frame = container.bounds
      material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      container.addSubview(material)
    }
  }

  func view() -> UIView { container }
}

private final class GlassControlsFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger

  init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    guard #available(iOS 26.0, *) else {
      return LiquidGlassView(frame: frame, dark: false, capsule: false)
    }
    let channel = FlutterMethodChannel(name: "horizon_link/controls/\(viewId)", binaryMessenger: messenger)
    // Flutter creates platform views on the platform (main) thread.
    return MainActor.assumeIsolated {
      GlassControls(frame: frame, options: args as? [String: Any] ?? [:], channel: channel)
    }
  }
}

// The system tab controller needs containment for UIKit to lay out its bar
// against the iPhone safe area and deliver appearance and trait changes.
private final class TabHostView: UIView {
  let tabs = UITabBarController()

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      if tabs.parent != nil {
        tabs.willMove(toParent: nil)
        tabs.view.removeFromSuperview()
        tabs.removeFromParent()
      }
      return
    }
    var ancestor: UIResponder? = next
    while let candidate = ancestor, !(candidate is UIViewController) {
      ancestor = candidate.next
    }
    guard let parent = ancestor as? UIViewController, tabs.parent == nil else { return }
    parent.addChild(tabs)
    tabs.view.frame = bounds
    tabs.view.autoresizingMask = [.flexibleHeight, .flexibleWidth]
    tabs.view.backgroundColor = .clear
    tabs.view.isOpaque = false
    addSubview(tabs.view)
    tabs.didMove(toParent: parent)
  }
}

@available(iOS 26.0, *)
private final class GlassControls: NSObject, FlutterPlatformView {
  private let channel: FlutterMethodChannel
  private let controls: SystemGlassControls
  private let root: UIView

  @MainActor
  init(frame: CGRect, options: [String: Any], channel: FlutterMethodChannel) {
    self.channel = channel
    let controls = SystemGlassControls(frame: frame, options: options) { index in
      channel.invokeMethod("activate", arguments: index)
    }
    self.controls = controls
    root = controls.root
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let options = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      // This channel uses Flutter's default platform-thread task queue.
      MainActor.assumeIsolated { self?.controls.update(options) }
      result(nil)
    }
  }

  func view() -> UIView { root }

  deinit { channel.setMethodCallHandler(nil) }
}

@available(iOS 26.0, *)
@MainActor
final class SystemGlassControls: NSObject {
  let root: UIView
  private let activate: (Int) -> Void
  private var buttons: [UIButton] = []

  init(frame: CGRect, options: [String: Any], activate: @escaping (Int) -> Void) {
    self.activate = activate
    let kind = options["kind"] as? String ?? "connection"
    switch kind {
    case "tabs": root = TabHostView(frame: frame)
    case "connection": root = UIStackView(frame: frame)
    default: root = OptionHostView(frame: frame, kind: kind, activate: activate)
    }
    super.init()
    if let host = root as? TabHostView {
      host.tabs.mode = .tabBar
      let symbols = ["gauge.with.dots.needle.67percent", "map", "book", "gearshape"]
      host.tabs.viewControllers = symbols.enumerated().map { index, symbol in
        let page = UIViewController()
        page.view.backgroundColor = .clear
        page.view.isOpaque = false
        let image = UIImage(systemName: symbol)
        page.tabBarItem = UITabBarItem(title: nil, image: image,
          selectedImage: UIImage(systemName: symbol + ".fill") ?? image)
        page.tabBarItem.tag = index
        return page
      }
      host.tabs.delegate = self
    } else if let stack = root as? UIStackView {
      stack.axis = .horizontal
      stack.distribution = .fillEqually
      stack.spacing = 12
      for index in 0..<2 {
        var configuration = UIButton.Configuration.glass()
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.addAction(UIAction { [weak self] _ in
          self?.activate(index)
        }, for: .primaryActionTriggered)
        buttons.append(button)
        stack.addArrangedSubview(button)
      }
    }
    update(options)
  }

  func update(_ options: [String: Any]) {
    guard let labels = options["labels"] as? [String] else { return }
    root.overrideUserInterfaceStyle = options["dark"] as? Bool == true ? .dark : .light
    let rgb = (options["accent"] as? NSNumber)?.uint32Value ?? 0
    let accent = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    root.tintColor = accent
    if let option = root as? OptionHostView {
      option.update(labels: labels, options: options, accent: accent)
      return
    }
    if let host = root as? TabHostView, let pages = host.tabs.viewControllers {
      host.tabs.overrideUserInterfaceStyle = root.overrideUserInterfaceStyle
      host.tabs.tabBar.tintColor = accent
      for (page, title) in zip(pages, labels) { page.tabBarItem.title = title }
      if let index = options["selected"] as? Int, pages.indices.contains(index),
         host.tabs.selectedIndex != index { host.tabs.selectedIndex = index }
    } else if let stack = root as? UIStackView {
      stack.axis = options["stacked"] as? Bool == true ? .vertical : .horizontal
      for (index, button) in buttons.enumerated() where labels.indices.contains(index) {
        var config = button.configuration
        config?.title = labels[index]
        config?.baseForegroundColor = index == 0 ? .label : accent
        button.configuration = config
      }
    }
  }

}

@available(iOS 26.0, *)
extension SystemGlassControls: UITabBarControllerDelegate {
  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    activate(tabBarController.selectedIndex)
  }
}

@available(iOS 26.0, *)
private final class OptionHostView: UIView {
  let kind: String
  let control: UIControl
  private let activate: (Int) -> Void
  private var titles: [String] = []

  init(frame: CGRect, kind: String, activate: @escaping (Int) -> Void) {
    self.kind = kind
    self.activate = activate
    switch kind {
    case "switch": control = UISwitch()
    case "segments": control = UISegmentedControl(items: [])
    default: control = UIButton(type: .system)
    }
    super.init(frame: frame)
    addSubview(control)
    control.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      control.centerYAnchor.constraint(equalTo: centerYAnchor),
      control.centerXAnchor.constraint(equalTo: centerXAnchor)
    ])
    if kind != "switch" {
      control.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    if let toggle = control as? UISwitch {
      toggle.addAction(UIAction { [weak self, weak toggle] _ in
        self?.activate(toggle?.isOn == true ? 1 : 0)
      }, for: .valueChanged)
    } else if let segments = control as? UISegmentedControl {
      segments.addAction(UIAction { [weak self, weak segments] _ in
        if let index = segments?.selectedSegmentIndex, index >= 0 { self?.activate(index) }
      }, for: .valueChanged)
    } else if let button = control as? UIButton {
      button.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
      button.showsMenuAsPrimaryAction = kind == "menu"
      if kind == "choice" {
        button.addAction(UIAction { [weak self] _ in self?.activate(0) }, for: .primaryActionTriggered)
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("Use init(frame:kind:activate:)") }

  func update(labels: [String], options: [String: Any], accent: UIColor) {
    let selected = options["selected"] as? Int ?? -1
    let name = options["name"] as? String ?? ""
    control.isEnabled = options["enabled"] as? Bool ?? true
    control.accessibilityLabel = name.isEmpty ? nil : name
    control.accessibilityHint = options["hint"] as? String
    if let toggle = control as? UISwitch {
      toggle.onTintColor = accent
      if toggle.isOn != (selected == 1) { toggle.setOn(selected == 1, animated: window != nil && !UIAccessibility.isReduceMotionEnabled) }
    } else if let segments = control as? UISegmentedControl {
      if titles != labels {
        segments.removeAllSegments()
        for (i, title) in labels.enumerated() { segments.insertSegment(withTitle: title, at: i, animated: false) }
      }
      segments.selectedSegmentIndex = selected
    } else if let button = control as? UIButton {
      let isMenu = kind == "menu"
      let symbol = options["symbol"] as? String ?? ""
      var config: UIButton.Configuration = !isMenu && selected == 0 ? .tinted() : .plain()
      config.cornerStyle = .capsule
      config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 3)
      config.titleLineBreakMode = .byTruncatingTail
      let current = labels.indices.contains(selected) ? labels[selected] : nil
      if !symbol.isEmpty {
        config.image = UIImage(systemName: symbol)
      } else {
        config.title = isMenu ? current : labels.first
        if isMenu {
          config.image = UIImage(systemName: "chevron.up.chevron.down")
          config.imagePlacement = .trailing
          config.imagePadding = 3
        }
      }
      button.configuration = config
      button.accessibilityValue = isMenu ? current : nil
      if !isMenu {
        if selected == 0 { button.accessibilityTraits.insert(.selected) }
        else { button.accessibilityTraits.remove(.selected) }
      } else {
        let destructive = options["destructive"] as? Int
        button.menu = UIMenu(children: labels.enumerated().map { index, title in
          UIAction(title: title, attributes: index == destructive ? .destructive : [],
            state: index == selected ? .on : .off) { [weak self] _ in
              guard let self = self, self.titles == labels, self.control.isEnabled else { return }
              self.activate(index)
            }
        })
      }
    }
    titles = labels
  }
}
