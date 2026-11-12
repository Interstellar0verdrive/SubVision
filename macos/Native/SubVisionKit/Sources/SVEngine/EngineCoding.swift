// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Models/EngineReplies.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation

/// The engine writes snake_case keys; decode replies and events with
/// `EngineCoding.decoder`, encode parameters with `EngineCoding.encoder`.
public enum EngineCoding {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
