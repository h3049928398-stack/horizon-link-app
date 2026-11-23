import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  @MainActor
  func testNativePreferencesSynchronizeAndReportUserChanges() throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS 26") }
    var changes: [Int] = []
    let toggle = SystemGlassControls(frame: .zero,
      options: ["kind": "switch", "labels": [], "name": "Record", "selected": 1]) { changes.append($0) }
    let control = try XCTUnwrap(toggle.root.subviews.first as? UISwitch)
    XCTAssertTrue(control.isOn)
    XCTAssertEqual(control.accessibilityLabel, "Record")
    control.setOn(false, animated: false)
    control.sendActions(for: .valueChanged)
    XCTAssertEqual(changes, [0])
    let segments = SystemGlassControls(frame: .zero, options: [
      "kind": "segments", "labels": ["km/h", "mph"], "selected": 0
    ]) { changes.append($0) }
    let units = try XCTUnwrap(segments.root.subviews.first as? UISegmentedControl)
    units.selectedSegmentIndex = 1
    units.sendActions(for: .valueChanged)
    XCTAssertEqual(changes, [0, 1])
    let options = SystemGlassControls(frame: .zero, options: [
      "kind": "menu", "labels": ["A", "B"], "selected": 1, "enabled": false
    ]) { changes.append($0) }
    let button = try XCTUnwrap(options.root.subviews.first as? UIButton)
    XCTAssertFalse(button.isEnabled)
    let actions = try XCTUnwrap(button.menu).children.compactMap { $0 as? UIAction }
    XCTAssertEqual(actions.map { $0.state }, [.off, .on])
    XCTAssertEqual(changes, [0, 1])
  }

  @MainActor
  func testConnectionButtonsUseSeparateNativeTargets() throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS 26") }
    var events: [Int] = []
    let controls = SystemGlassControls(frame: CGRect(x: 0, y: 0, width: 320, height: 48),
      options: ["kind": "connection", "labels": ["Close", "Start listening"]]) { events.append($0) }
    let stack = try XCTUnwrap(controls.root as? UIStackView)
    stack.layoutIfNeeded()
    let buttons = stack.arrangedSubviews.compactMap { $0 as? UIButton }
    XCTAssertEqual(buttons.map { $0.configuration?.title ?? "" }, ["Close", "Start listening"])
    guard buttons.count == 2 else { return XCTFail("Expected two buttons") }
    XCTAssertLessThan(buttons[0].frame.maxX, buttons[1].frame.minX)
    for button in buttons { button.sendActions(for: .primaryActionTriggered) }
    XCTAssertEqual(events, [0, 1])
  }

  @MainActor
  func testTabControllerFollowsFlutterMapSelectionAndDetaches() throws {
    guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS 26") }
    let parent = UIViewController()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = parent
    window.isHidden = false
    defer { window.isHidden = true }
    let labels = ["Dashboard", "Map", "Guides", "Settings"]
    var events: [Int] = []
    let controls = SystemGlassControls(frame: CGRect(x: 0, y: 740, width: 390, height: 104),
      options: ["kind": "tabs", "labels": labels, "selected": 2]) { events.append($0) }
    parent.view.addSubview(controls.root)
    let tabs = try XCTUnwrap(parent.children.first as? UITabBarController)
    XCTAssertEqual(tabs.tabBar.items?.compactMap { $0.title }, labels)
    XCTAssertEqual(tabs.selectedIndex, 2)
    controls.update(["labels": labels, "selected": 1])
    XCTAssertEqual(tabs.selectedIndex, 1)
    XCTAssertTrue(events.isEmpty)
    controls.root.removeFromSuperview()
    XCTAssertTrue(parent.children.isEmpty)
  }

  func testLiquidGlassRespectsSystemSupportAndReduceTransparency() {
    XCTAssertTrue(LiquidGlassBridge.enabled(supportsMaterial: true, reduceTransparency: false))
    XCTAssertFalse(LiquidGlassBridge.enabled(supportsMaterial: true, reduceTransparency: true))
    XCTAssertFalse(LiquidGlassBridge.enabled(supportsMaterial: false, reduceTransparency: false))
  }

  func testBoundedDocumentReadPreservesUTF8() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let data = Data("{\"version\":2,\"name\":\"仪表\"}".utf8)
    try data.write(to: url)
    XCTAssertEqual(try LocalDocuments.readBounded(url), data)
  }

  func testOversizeDocumentIsRejected() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: UInt64(LocalDocuments.byteLimit + 1))
    try handle.close()
    XCTAssertThrowsError(try LocalDocuments.readBounded(url))
  }

}
