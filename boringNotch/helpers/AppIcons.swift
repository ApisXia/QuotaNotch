//
//  AppIcons.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import SwiftUI
import AppKit

struct AppIcons {
    
    func getIcon(file path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path)
        else { return nil }
        
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    func getIcon(bundleID: String) -> NSImage? {
        guard let path = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        )?.absoluteString
        else { return nil }
        
        return getIcon(file: path)
    }
    
        /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }
        
        return Bundle(url: url)
    }
    
}

/// Browsers report playback from helper processes ("com.google.Chrome.helper",
/// "com.apple.WebKit.GPU"); map those back to the app itself. (From boring.notch dev.)
func normalizeBundleIdentifier(_ bundleID: String) -> String {
    let lower = bundleID.lowercased()
    if lower.hasPrefix("com.apple.safaritechnologypreview.") {
        return "com.apple.SafariTechnologyPreview"
    }
    if lower.hasPrefix("com.apple.webkit.") || lower.hasPrefix("com.apple.safari.") {
        return "com.apple.Safari"
    }
    let components = bundleID.components(separatedBy: ".")
    if let helperIndex = components.firstIndex(where: { $0.lowercased() == "helper" }), helperIndex > 0 {
        return components[0..<helperIndex].joined(separator: ".")
    }
    return bundleID
}

func AppIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizeBundleIdentifier(bundleID)) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }
    
    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizeBundleIdentifier(bundleID)) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

