#!/usr/bin/env swift
// Captures the main window of a running app to a PNG (development aid).
//   swift scripts/capture-window.swift <app name> <output.png>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: capture-window.swift <app name> <output.png>")
    exit(2)
}
let appName = args[1]
guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    print("cannot list windows")
    exit(1)
}
let candidates = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == appName && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0 }
guard let window = candidates.first, let number = window[kCGWindowNumber as String] as? Int else {
    print("no on-screen window for \(appName)")
    exit(1)
}
let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
print("window \(number) bounds \(bounds)")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-x", "-o", "-l", String(number), args[2]]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "saved \(args[2])" : "screencapture failed")
