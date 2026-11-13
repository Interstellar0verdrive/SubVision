// SPDX-License-Identifier: MIT
// The OCR parameters of the inspector (design boards I1–I3, D5), kept in
// UserDefaults one key per parameter so the inspector (`@AppStorage`), the
// band handles of Preview and the note of Sub fix read and write the same
// values. `AppModel.ocrParams` builds the `OcrParams` of `batch.start`,
// `preview.*` and `srt.fix` from them; a missing key means the engine's default.

import Foundation
import SVShell

/// The UserDefaults keys, one per field of `OcrParams`, plus the two lists.
enum OcrKey {
    static let fps = "ocr.fps"
    /// The OCR language: the same key `DefaultsKey.ocrLanguage` (the warm-up reads it).
    static let langHint = DefaultsKey.ocrLanguage
    static let bottomKeepPct = "ocr.bottomKeepPct"
    static let keepWPct = "ocr.keepWPct"
    static let topBand = "ocr.topBand"
    static let topKeepPct = "ocr.topKeepPct"
    static let topKeepWPct = "ocr.topKeepWPct"
    static let recognitionLevel = "ocr.recognitionLevel"
    static let minConfidence = "ocr.minConfidence"
    static let multiVariant = "ocr.multiVariant"
    static let skipHamming = "ocr.skipHamming"
    static let refineTiming = "ocr.refineTiming"
    static let minDuration = "ocr.minDuration"
    static let mergeGap = "ocr.mergeGap"
    static let wrapWidth = "ocr.wrapWidth"
    static let workers = "ocr.workers"
    static let qcReport = "ocr.qcReport"
    static let qcGapWarn = "ocr.qcGapWarn"
    static let qcConfWarn = "ocr.qcConfWarn"
    static let qcAgreeWarn = "ocr.qcAgreeWarn"
    static let useIgnore = "ocr.useIgnore"
    static let useCorrections = "ocr.useCorrections"

    /// Every parameter key (not the lists): "Reset all defaults" removes them.
    static let all = [fps, langHint, bottomKeepPct, keepWPct, topBand, topKeepPct, topKeepWPct, recognitionLevel,
                      minConfidence, multiVariant, skipHamming, refineTiming, minDuration, mergeGap, wrapWidth,
                      workers, qcReport, qcGapWarn, qcConfWarn, qcAgreeWarn]
}

/// The engine's defaults, the ones "Default" goes back to.
let ocrDefaults = OcrParams()

extension UserDefaults {
    /// A typed read with the default when the key is absent (or of another type).
    func value<T>(_ key: String, or fallback: T) -> T {
        object(forKey: key) as? T ?? fallback
    }
}

extension AppModel {
    /// The parameters as the inspector set them, for every engine request.
    var ocrParams: OcrParams {
        let d = defaults, o = ocrDefaults
        var p = OcrParams()
        p.fps = d.value(OcrKey.fps, or: o.fps)
        p.langHint = d.string(forKey: OcrKey.langHint) ?? o.langHint
        p.bottomKeepPct = d.value(OcrKey.bottomKeepPct, or: o.bottomKeepPct)
        p.keepWPct = d.value(OcrKey.keepWPct, or: o.keepWPct)
        p.topBand = d.value(OcrKey.topBand, or: o.topBand)
        p.topKeepPct = d.value(OcrKey.topKeepPct, or: o.topKeepPct)
        p.topKeepWPct = d.value(OcrKey.topKeepWPct, or: o.topKeepWPct)
        p.recognitionLevel = d.string(forKey: OcrKey.recognitionLevel) ?? o.recognitionLevel
        p.minConfidence = d.value(OcrKey.minConfidence, or: o.minConfidence)
        p.multiVariant = d.value(OcrKey.multiVariant, or: o.multiVariant)
        p.skipHamming = d.value(OcrKey.skipHamming, or: o.skipHamming)
        p.refineTiming = d.value(OcrKey.refineTiming, or: o.refineTiming)
        p.minDuration = d.value(OcrKey.minDuration, or: o.minDuration)
        p.mergeGap = d.value(OcrKey.mergeGap, or: o.mergeGap)
        p.wrapWidth = d.value(OcrKey.wrapWidth, or: o.wrapWidth)
        p.workers = d.value(OcrKey.workers, or: o.workers)
        p.qcReport = d.value(OcrKey.qcReport, or: o.qcReport)
        p.qcGapWarn = d.value(OcrKey.qcGapWarn, or: o.qcGapWarn)
        p.qcConfWarn = d.value(OcrKey.qcConfWarn, or: o.qcConfWarn)
        p.qcAgreeWarn = d.value(OcrKey.qcAgreeWarn, or: o.qcAgreeWarn)
        return p
    }

    var useIgnore: Bool { defaults.value(OcrKey.useIgnore, or: true) }
    var useCorrections: Bool { defaults.value(OcrKey.useCorrections, or: true) }

    /// Writes a whole profile (the `DebugQA` scenarios use `.fast`).
    func applyOcrParams(_ p: OcrParams) {
        let d = defaults
        d.set(p.fps, forKey: OcrKey.fps)
        d.set(p.langHint, forKey: OcrKey.langHint)
        d.set(p.bottomKeepPct, forKey: OcrKey.bottomKeepPct)
        d.set(p.keepWPct, forKey: OcrKey.keepWPct)
        d.set(p.topBand, forKey: OcrKey.topBand)
        d.set(p.topKeepPct, forKey: OcrKey.topKeepPct)
        d.set(p.topKeepWPct, forKey: OcrKey.topKeepWPct)
        d.set(p.recognitionLevel, forKey: OcrKey.recognitionLevel)
        d.set(p.minConfidence, forKey: OcrKey.minConfidence)
        d.set(p.multiVariant, forKey: OcrKey.multiVariant)
        d.set(p.skipHamming, forKey: OcrKey.skipHamming)
        d.set(p.refineTiming, forKey: OcrKey.refineTiming)
        d.set(p.minDuration, forKey: OcrKey.minDuration)
        d.set(p.mergeGap, forKey: OcrKey.mergeGap)
        d.set(p.wrapWidth, forKey: OcrKey.wrapWidth)
        d.set(p.workers, forKey: OcrKey.workers)
        d.set(p.qcReport, forKey: OcrKey.qcReport)
        d.set(p.qcGapWarn, forKey: OcrKey.qcGapWarn)
        d.set(p.qcConfWarn, forKey: OcrKey.qcConfWarn)
        d.set(p.qcAgreeWarn, forKey: OcrKey.qcAgreeWarn)
    }

    /// "Reset all defaults" (design note 14): the keys go, the engine's defaults are back.
    func resetOcrParams() {
        for key in OcrKey.all { defaults.removeObject(forKey: key) }
    }
}
