// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Sources/Models/Localizer.swift),
// by the same author. SubVision does not depend on AnimeUp. Changed here:
// languages, fallback and plural suffixes come from the initialiser, the
// catalogues can be loaded from a bundle, and `missingKeys` compares two
// languages for the catalogue tests.

import Foundation
import Observation

/// The app's texts, from JSON catalogues: `<folder>/<language>/*.json`, one
/// file per area, the same keys in every language, string values only.
///
/// A key that is missing in the active language falls back to `fallback`,
/// then to the key itself. Placeholders are `{name}` fields filled from a
/// dictionary; plurals are `<key><pluralSuffixes.one>` /
/// `<key><pluralSuffixes.other>` (`.uno` / `.altri` by default).
///
/// Format specs (`{x:.1f}`) are not supported: the engine sends numbers and
/// the app formats them in Swift before calling `t`. A `{name:spec}` field
/// is tolerated, the spec is ignored.
///
/// Observable: views that call `t` redraw when `language` changes, so the
/// switch between languages is live.
@Observable
public final class Localizer: @unchecked Sendable {
    public struct PluralSuffixes: Sendable, Equatable {
        public var one: String
        public var other: String

        public init(one: String, other: String) {
            self.one = one
            self.other = other
        }

        /// `<key>.uno` / `<key>.altri`.
        public static let standard = PluralSuffixes(one: ".uno", other: ".altri")
    }

    /// The keys of one language that the other lacks.
    public struct MissingKeys: Sendable, Equatable {
        public var onlyInFirst: Set<String>
        public var onlyInSecond: Set<String>
        public var isEmpty: Bool { onlyInFirst.isEmpty && onlyInSecond.isEmpty }
    }

    /// Language codes, in the order the app shows them.
    @ObservationIgnored public let languages: [String]
    @ObservationIgnored public let fallback: String
    @ObservationIgnored public let pluralSuffixes: PluralSuffixes
    public private(set) var language: String
    private var catalogs: [String: [String: String]] = [:]

    /// Catalogues already in memory: `[language: [key: text]]`.
    public init(catalogs: [String: [String: String]], languages: [String], fallback: String = "en",
                pluralSuffixes: PluralSuffixes = .standard, language: String? = nil) {
        precondition(languages.contains(fallback), "the fallback must be one of the languages")
        self.languages = languages
        self.fallback = fallback
        self.pluralSuffixes = pluralSuffixes
        self.language = fallback
        for code in languages { self.catalogs[code] = catalogs[code] ?? [:] }
        if let language { setLanguage(language) }
    }

    /// `folder` holds one subfolder per language; nil gives a localiser that
    /// shows keys.
    public convenience init(folder: URL?, languages: [String], fallback: String = "en",
                            pluralSuffixes: PluralSuffixes = .standard, language: String? = nil) {
        var catalogs: [String: [String: String]] = [:]
        if let folder {
            for code in languages { catalogs[code] = Self.load(folder.appendingPathComponent(code)) }
        }
        self.init(catalogs: catalogs, languages: languages, fallback: fallback,
                  pluralSuffixes: pluralSuffixes, language: language)
    }

    /// The catalogues shipped in a bundle under `subdirectory` (the app's
    /// `locales`, or a test target's fixtures).
    public convenience init(bundle: Bundle, subdirectory: String = "locales", languages: [String],
                            fallback: String = "en", pluralSuffixes: PluralSuffixes = .standard,
                            language: String? = nil) {
        self.init(folder: bundle.resourceURL?.appendingPathComponent(subdirectory), languages: languages,
                  fallback: fallback, pluralSuffixes: pluralSuffixes, language: language)
    }

    /// Switches to `code` if it's one of the languages, to the fallback otherwise.
    public func setLanguage(_ code: String) {
        let valid = languages.contains(code) ? code : fallback
        if valid != language { language = valid }
    }

    /// The language to start in on first launch: the first of `preferred`
    /// (macOS's list by default) that's one of ours, else the fallback.
    public func systemLanguage(preferred: [String] = Locale.preferredLanguages) -> String {
        for item in preferred {
            let code = String(item.prefix(2))
            if languages.contains(code) { return code }
        }
        return fallback
    }

    public func t(_ key: String, _ values: [String: Any] = [:]) -> String {
        let text = catalogs[language]?[key] ?? catalogs[fallback]?[key] ?? key
        return Self.format(text, values)
    }

    /// `<key>.uno` for 1, `<key>.altri` otherwise, with `{n}` set.
    public func tn(_ key: String, _ n: Int, _ values: [String: Any] = [:]) -> String {
        var all = values
        all["n"] = n
        return t(key + (n == 1 ? pluralSuffixes.one : pluralSuffixes.other), all)
    }

    /// The locale of the active language: the engine sends plain numbers and
    /// the rows show them as the boards do ("1.840 / 17.000 · 7,3 fps" in Italian).
    public var locale: Locale { Locale(identifier: language) }

    /// `value` with `decimals` digits and the language's separators.
    public func number(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    /// Every time of the app, always with two digits (design note 70): `04:12`, `00:48`, `01:02:03`.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// The key exists in the fallback language.
    public func has(_ key: String) -> Bool { catalogs[fallback]?[key] != nil }

    public func keys(_ code: String) -> Set<String> { Set(catalogs[code]?.keys ?? [:].keys) }

    /// For the catalogue test: every key must exist in both languages.
    public func missingKeys(between first: String, and second: String) -> MissingKeys {
        let a = keys(first), b = keys(second)
        return MissingKeys(onlyInFirst: a.subtracting(b), onlyInSecond: b.subtracting(a))
    }

    /// `{name}` filled from `values`; `{{` and `}}` are literal braces; an
    /// unknown field is left as it is.
    public static func format(_ text: String, _ values: [String: Any]) -> String {
        guard text.contains("{") || text.contains("}") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if c == "{", next < text.endIndex, text[next] == "{" {
                out.append("{"); i = text.index(after: next); continue
            }
            if c == "}", next < text.endIndex, text[next] == "}" {
                out.append("}"); i = text.index(after: next); continue
            }
            if c == "{", let close = text[next...].firstIndex(of: "}") {
                let field = String(text[next..<close])
                let name = field.split(separator: ":", maxSplits: 1).first.map(String.init) ?? field
                if let v = values[name] { out.append("\(v)") } else { out.append("{\(field)}") }
                i = text.index(after: close)
                continue
            }
            out.append(c)
            i = next
        }
        return out
    }

    /// Every `*.json` in `folder`, merged (files in name order; string values only).
    static func load(_ folder: URL) -> [String: String] {
        var merged: [String: String] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (k, v) in dict { if let s = v as? String { merged[k] = s } }
        }
        return merged
    }
}
