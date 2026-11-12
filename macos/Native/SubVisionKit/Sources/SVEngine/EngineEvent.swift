// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Engine/EngineClient.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation

/// A push message from the engine (no request id): `batch.step`,
/// `tools.progress`... plus the client's own `engine.started`,
/// `engine.exited` and `engine.gave_up`.
public struct EngineEvent: Sendable {
    public var name: String
    /// The raw JSON of `data` (an object, possibly empty).
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    /// `data` as a typed value (snake_case keys become camelCase).
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try EngineCoding.decoder.decode(T.self, from: data)
    }

    /// `data` as a plain dictionary, for the odd field read without a type.
    public func dictionary() throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EngineError.badReply("event \(name): data is not an object")
        }
        return object
    }
}
