import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift list_app_windows.swift <application name>\n", stderr)
    exit(2)
}

let applicationName = CommandLine.arguments[1]
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

let matching = windows.compactMap { window -> (Int, String, CGRect)? in
    guard window[kCGWindowOwnerName as String] as? String == applicationName,
          window[kCGWindowLayer as String] as? Int == 0,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? NSNumber,
          let y = bounds["Y"] as? NSNumber,
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber,
          case let rect = CGRect(
              x: x.doubleValue,
              y: y.doubleValue,
              width: width.doubleValue,
              height: height.doubleValue
          ),
          rect.width > 0,
          rect.height > 0 else {
        return nil
    }
    let title = (window[kCGWindowName as String] as? String ?? "")
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    return (number, title, rect)
}.sorted { $0.0 < $1.0 }

for (number, title, rect) in matching {
    let bounds = "{{\(Int(rect.origin.x)),\(Int(rect.origin.y))},{\(Int(rect.width)),\(Int(rect.height))}}"
    print("\(number)\t\(applicationName)\t\(title)\t\(bounds)")
}
