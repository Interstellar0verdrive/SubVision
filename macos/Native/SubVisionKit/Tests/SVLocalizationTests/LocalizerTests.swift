// SPDX-License-Identifier: MIT
// Adapted from the AnimeUp native app (AnimeUpKit/Tests/ModelsTests/ModelsTests.swift),
// by the same author. SubVision does not depend on AnimeUp.

import Foundation
import Testing
@testable import SVLocalization

@Suite struct LocalizerTests {
    func fixtures(language: String? = nil) -> Localizer {
        Localizer(bundle: .module, subdirectory: "Fixtures", languages: ["en", "it"], language: language)
    }

    @Test func loadsEveryFileOfTheBundleFolder() {
        let l = fixtures()
        #expect(l.language == "en")
        #expect(l.t("x.hello", ["name": "Ada"]) == "Hello Ada")
        #expect(l.t("y.second_file") == "from the second file")
        #expect(l.has("x.hello") && !l.has("y.not_a_string"))
    }

    @Test func liveSwitch() {
        let l = fixtures(language: "it")
        #expect(l.language == "it")
        #expect(l.t("x.hello", ["name": "Ada"]) == "Ciao Ada")
        l.setLanguage("en")
        #expect(l.t("x.hello", ["name": "Ada"]) == "Hello Ada")
        l.setLanguage("fr")
        #expect(l.language == "en")
    }

    @Test func plurals() {
        let l = fixtures()
        #expect(l.tn("x.files", 1) == "one file")
        #expect(l.tn("x.files", 3) == "3 files")
        l.setLanguage("it")
        #expect(l.tn("x.files", 1) == "un file")
        #expect(l.tn("x.files", 0) == "0 file")
    }

    @Test func fallbackAndMissingKeys() {
        let l = fixtures(language: "it")
        #expect(l.t("x.only_en") == "English only")
        #expect(l.t("x.only_it") == "Solo italiano")
        #expect(l.t("missing.key") == "missing.key")
        l.setLanguage("en")
        #expect(l.t("x.only_it") == "x.only_it")
    }

    @Test func formatBraces() {
        let l = fixtures()
        #expect(l.t("x.braces", ["a": 1]) == "{literal} 1")
        #expect(Localizer.format("{{literal}} {a} {b:.1f}", ["a": 1, "b": "2.0"]) == "{literal} 1 2.0")
        #expect(Localizer.format("{unknown}", [:]) == "{unknown}")
        #expect(Localizer.format("no fields", ["a": 1]) == "no fields")
    }

    @Test func systemLanguage() {
        let l = fixtures()
        #expect(l.systemLanguage(preferred: ["fr-FR", "it-IT", "en"]) == "it")
        #expect(l.systemLanguage(preferred: ["fr-FR"]) == "en")
        #expect(l.systemLanguage(preferred: []) == "en")
    }

    @Test func customSuffixesAndInMemoryCatalogs() {
        let l = Localizer(catalogs: ["en": ["n_one": "one", "n_other": "{n}"], "it": ["n_one": "uno", "n_other": "{n}"]],
                          languages: ["en", "it"], pluralSuffixes: .init(one: "_one", other: "_other"))
        #expect(l.tn("n", 1) == "one" && l.tn("n", 2) == "2")
        l.setLanguage("it")
        #expect(l.tn("n", 1) == "uno")
    }

    @Test func noFolderShowsKeys() {
        let l = Localizer(folder: nil, languages: ["en", "it"])
        #expect(l.t("a.b") == "a.b" && l.keys("en").isEmpty)
    }

    /// The check F4 runs on the real catalogues: the same keys in every language.
    @Test func missingKeysBetweenLanguages() {
        let fixtures = fixtures()
        let missing = fixtures.missingKeys(between: "en", and: "it")
        #expect(missing.onlyInFirst == ["x.only_en"])
        #expect(missing.onlyInSecond == ["x.only_it"])
        #expect(!missing.isEmpty)
        let same = Localizer(catalogs: ["en": ["k": "a"], "it": ["k": "b"]], languages: ["en", "it"])
        #expect(same.missingKeys(between: "en", and: "it").isEmpty)
    }
}
