// SPDX-License-Identifier: MIT
// The app's catalogues (Resources/locales/<lang>/app.json): the two languages
// must have the same keys, the same placeholders and complete plural pairs,
// and every text the shell takes from them must be there.

import Foundation
import SVShell
import Testing

@Suite struct CatalogueTests {
    static let languages = ["en", "it"]

    /// The catalogues as the test bundle carries them (the same folder the app ships).
    static func localizer(language: String = "en") -> Localizer {
        Localizer(bundle: Bundle(for: Marker.self), subdirectory: "locales", languages: languages, language: language)
    }

    private final class Marker {}

    @Test func bothLanguagesAreLoaded() {
        let l = Self.localizer()
        #expect(l.keys("en").count > 500, "the English catalogue is missing or short: \(l.keys("en").count) keys")
        #expect(l.keys("it").count == l.keys("en").count)
    }

    @Test func sameKeysInEnglishAndItalian() {
        let missing = Self.localizer().missingKeys(between: "en", and: "it")
        #expect(missing.onlyInFirst.isEmpty, "only in en: \(missing.onlyInFirst.sorted())")
        #expect(missing.onlyInSecond.isEmpty, "only in it: \(missing.onlyInSecond.sorted())")
    }

    @Test func samePlaceholdersInBothLanguages() {
        let en = Self.localizer(language: "en"), it = Self.localizer(language: "it")
        var wrong: [String] = []
        for key in en.keys("en").sorted() {
            if Self.fields(en.t(key)) != Self.fields(it.t(key)) { wrong.append(key) }
        }
        #expect(wrong.isEmpty, "placeholders differ: \(wrong)")
    }

    @Test func pluralPairsAreComplete() {
        let keys = Self.localizer().keys("en")
        var lonely: [String] = []
        for key in keys where key.hasSuffix(".uno") || key.hasSuffix(".altri") {
            let stem = key.hasSuffix(".uno") ? String(key.dropLast(4)) : String(key.dropLast(6))
            if !(keys.contains(stem + ".uno") && keys.contains(stem + ".altri")) { lonely.append(key) }
        }
        #expect(lonely.isEmpty, "plural without its pair: \(lonely)")
    }

    @Test func everyShellTextHasItsKey() {
        let l = Self.localizer()
        let missing = ShellTexts.catalogue.map(\.1).filter { !(l.keys("en").contains($0) && l.keys("it").contains($0)) }
        #expect(missing.isEmpty, "shell keys missing from the catalogues: \(missing)")
    }

    /// 11.3.4: a tool that exits with an error is worded by the app, in the language of the app.
    @Test func toolExitIsWordedInEachLanguage() {
        let args: [String: Any] = ["tool": "ffmpeg", "status": 69]
        #expect(Self.localizer(language: "en").t("app.errors.tool_exit", args) == "ffmpeg exited with status 69")
        #expect(Self.localizer(language: "it").t("app.errors.tool_exit", args) == "ffmpeg è uscito con il codice 69")
    }

    /// `{name}` fields of a text, as a multiset.
    static func fields(_ text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            let after = rest.index(after: open)
            if after < rest.endIndex, rest[after] == "{" { rest = rest[rest.index(after: after)...]; continue }
            guard let close = rest[after...].firstIndex(of: "}") else { break }
            out.append(String(rest[after..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return out.sorted()
    }
}
