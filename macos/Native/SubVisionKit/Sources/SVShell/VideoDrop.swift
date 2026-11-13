// SPDX-License-Identifier: MIT
// The drop of videos onto a view: the app of AnimeUp (by the same author)
// let the engine walk folders; here the app walks them itself, so a page can
// take files and folders with the same closure.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Finds the video files among dropped items, inside folders too.
public enum VideoScan {
    /// Lower-case extensions the app opens.
    public static let defaultExtensions: Set<String> = ["mp4", "mkv", "mov", "m4v", "avi", "webm", "ts", "mpg", "mpeg", "wmv", "flv"]

    /// The files among `urls` with one of `extensions`, plus those inside any
    /// folder (its subfolders too when `recursive`). Hidden files and package
    /// contents are skipped; the order is the drop's, folders walked in name order.
    public static func videos(in urls: [URL], extensions: Set<String> = defaultExtensions, recursive: Bool = true) -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []
        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard extensions.contains(url.pathExtension.lowercased()), !seen.contains(path) else { return }
            seen.insert(path)
            out.append(url)
        }
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue { add(url); continue }
            let options: FileManager.DirectoryEnumerationOptions = recursive
                ? [.skipsHiddenFiles, .skipsPackageDescendants]
                : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
            guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: options) else { continue }
            var found: [URL] = []
            for case let file as URL in walker {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { found.append(file) }
            }
            for file in found.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) { add(file) }
        }
        return out
    }
}

extension View {
    /// Takes dropped files and folders and hands over every item as it came
    /// (the app sorts videos from the rest, to say what it skipped).
    public func fileDrop(isTargeted: Binding<Bool>? = nil, action: @escaping ([URL]) -> Void) -> some View {
        onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            Task { @MainActor in action(await droppedURLs(providers)) }
            return true
        }
    }

    /// Takes dropped files and folders and hands over the videos found in them
    /// (`extensions: ["srt"], recursive: false` for Sub fix). `isTargeted`
    /// follows the drag, for a highlight; `onEmpty` gets the dropped items
    /// when none matched (a folder without videos: alert O8a).
    public func videoDrop(extensions: Set<String> = VideoScan.defaultExtensions, recursive: Bool = true,
                          isTargeted: Binding<Bool>? = nil, onEmpty: (([URL]) -> Void)? = nil,
                          action: @escaping ([URL]) -> Void) -> some View {
        onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            Task { @MainActor in
                let urls = await droppedURLs(providers)
                let videos = VideoScan.videos(in: urls, extensions: extensions, recursive: recursive)
                if !videos.isEmpty { action(videos) } else if !urls.isEmpty { onEmpty?(urls) }
            }
            return true
        }
    }
}

/// The file URLs of dropped items, in the drop's order.
@MainActor
func droppedURLs(_ providers: [NSItemProvider]) async -> [URL] {
    var urls: [URL] = []
    for provider in providers {
        if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
            urls.append(url)
        } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) {
            urls.append(url)
        }
    }
    return urls
}
