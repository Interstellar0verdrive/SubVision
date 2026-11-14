// SPDX-License-Identifier: MIT
// SVShell: the app frame. The app keeps its model, its pages and its texts;
// the shell gives it the window chrome, the top bar, the engine
// status, the first-launch tools window, the log, the Dock, notifications,
// the update check and the debug helpers.

@_exported import SVDesign
@_exported import SVEngine
@_exported import SVLocalization

/// Version of the package and the list of its modules.
public enum SubVisionKit {
    public static let version = "0.1.0"
    public static let modules = ["SVEngine", "SVDesign", "SVLocalization", "SVShell"]
}
