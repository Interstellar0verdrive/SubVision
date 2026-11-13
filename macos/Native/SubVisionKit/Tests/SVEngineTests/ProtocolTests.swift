// SPDX-License-Identifier: MIT
// The replies and events as src/subvision/serve.py, batch.py, preview.py and
// tools.py write them (one sample each, keys and nulls as the engine sends).

import Foundation
import Testing
@testable import SVEngine

private func event(_ name: String, _ json: String) throws -> EngineMessage {
    try EngineEvent(name: name, data: Data(json.utf8)).message()
}

private func reply<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
    try EngineCoding.decoder.decode(T.self, from: Data(json.utf8))
}

@Suite struct ProtocolTests {
    @Test func batchEvents() throws {
        let started = try event("batch.file.started", #"""
            {"idx":0,"total":2,"name":"ep01.mkv","srt":"/v/ep01.srt","log":"/v/ep01.log","report":null,
             "steps":[{"key":"extract","band":"bottom","estimate":null},{"key":"ocr","band":"bottom","estimate":41.5}]}
            """#)
        guard case .batchFileStarted(let s) = started else { Issue.record("\(started)"); return }
        #expect(s.steps.map(\.id) == ["extract:bottom", "ocr:bottom"] && s.steps[1].estimate == 41.5 && s.report == nil)

        let step = try event("batch.step", #"""
            {"idx":0,"step":"ocr","band":"bottom","ratio":0.25,"count":10,"total":40,"unit":"frames",
             "elapsed":3.2,"eta":null,"rate":3.1}
            """#)
        #expect(step == .batchStep(BatchStep(idx: 0, step: "ocr", band: "bottom", ratio: 0.25, count: 10, total: 40,
                                             unit: "frames", elapsed: 3.2, eta: nil, rate: 3.1)))

        let done = try event("batch.file.done", #"""
            {"idx":0,"segments":12,"dropped":1,"refined":5,"elapsed":61.0,
             "times":{"extract:bottom":20.5,"ocr:bottom":40.5},"srt":"/v/ep01.srt",
             "report":"/v/ep01.review.html","log":"/v/ep01.log","empty":false}
            """#)
        guard case .batchFileDone(let d) = done else { Issue.record("\(done)"); return }
        #expect(d.times["extract:bottom"] == 20.5 && d.segments == 12 && !d.empty)

        #expect(try event("batch.file.failed", #"{"idx":1,"error":"probe_failed (path=/v/x.mkv)","at_step":"extract:bottom"}"#)
                == .batchFileFailed(BatchFileFailed(idx: 1, error: "probe_failed (path=/v/x.mkv)", atStep: "extract:bottom")))
        #expect(try event("batch.file.stopped", #"{"idx":1}"#) == .batchFileStopped(BatchFileStopped(idx: 1)))
        #expect(try event("batch.done", #"{"done":1,"failed":0,"stopped":1,"skipped":0,"elapsed":90.1}"#)
                == .batchDone(BatchDone(done: 1, failed: 0, stopped: 1, skipped: 0, elapsed: 90.1, error: nil)))
    }

    @Test func previewEventsAndTest() throws {
        #expect(try event("preview.progress", #"{"done":3,"total":20,"found":2,"found_top":1}"#)
                == .previewProgress(PreviewProgress(done: 3, total: 20, found: 2, foundTop: 1)))
        #expect(try event("preview.progress", #"{"done":3,"total":20,"found":2}"#)
                == .previewProgress(PreviewProgress(done: 3, total: 20, found: 2)))
        let done = try event("preview.done", #"""
            {"frames":[{"path":"/s/tmp/preview/ab/000.jpg","bands":["bottom","top"],"has_text":true,"width":1920,"height":1080,"ts":12.5},
                       {"path":"/s/tmp/preview/ab/001.jpg","bands":[],"has_text":false,"width":1920,"height":1080,"ts":40.0},
                       {"path":"/s/tmp/preview/ab/002.jpg","bands":["top"],"has_text":true,"width":1920,"height":1080,"ts":52.0}]}
            """#)
        guard case .previewDone(let p) = done else { Issue.record("\(done)"); return }
        #expect(p.frames.map(\.hasText) == [true, false, true] && p.frames[1].bands.isEmpty)
        #expect(p.frames.map(\.hasDialogue) == [true, false, false] && p.frames.map(\.hasSigns) == [true, false, true])
        #expect(try event("preview.stopped", "{}") == .previewStopped)
        #expect(try event("preview.failed", #"{"error":"invalid_duration","message":"invalid_duration (path=/v)"}"#)
                == .previewFailed(PreviewFailed(error: "invalid_duration", message: "invalid_duration (path=/v)")))

        let test = try reply(#"""
            {"bands":{"bottom":{"text":"Ciao","conf":0.91,"agree":1.0,"alts":["Ciao!"],"final":"Ciao","ms":120.4,"variants":3,"empty":false},
                      "top":{"text":"","conf":0.0,"agree":1.0,"alts":[],"final":"","ms":80.0,"variants":3,"empty":true}}}
            """#, as: OcrTestReply.self)
        #expect(test.bottom?.finalText == "Ciao" && test.bottom?.alts == ["Ciao!"] && test.top?.empty == true)
    }

    @Test func toolsAndWarmup() throws {
        let status = try reply(#"""
            {"tools":{"ffprobe":{"present":true,"path":"/s/bin/ffprobe","version":"9.0.2"},
                      "ffmpeg":{"present":false,"path":"/s/bin/ffmpeg","version":null}},
             "active":null,"custom":null}
            """#, as: ToolsStatusReply.self)
        #expect(status.tools.map(\.key) == ["ffmpeg", "ffprobe"])
        #expect(status.missingKeys == ["ffmpeg"] && !status.allPresent && status.active == nil)

        #expect(try event("tools.progress", #"{"key":"ffmpeg","state":"failed","bytes":0,"total":0,"error":"checksum"}"#)
                == .toolsProgress(ToolProgress(key: "ffmpeg", state: .failed, bytes: 0, total: 0, error: "checksum")))
        let done = try event("tools.done", #"""
            {"ok":true,"status":{"tools":{"ffmpeg":{"present":true,"path":"/s/bin/ffmpeg","version":"9.0.2"}},
             "active":{"path":"/s/bin/ffmpeg","version":"9.0.2"},"custom":null}}
            """#)
        guard case .toolsDone(let t) = done else { Issue.record("\(done)"); return }
        #expect(t.ok && t.status.allPresent && t.status.active?.version == "9.0.2")
        #expect(try event("warmup.done", #"{"seconds":31.02,"languages":["it-IT"]}"#)
                == .warmupDone(WarmupDone(seconds: 31.02, languages: ["it-IT"])))

        let busy = try reply(#"{"started":false,"reason":"busy"}"#, as: StartReply.self)
        #expect(busy.isBusy)
        let install = try reply(#"{"started":true,"keys":["ffmpeg","ffprobe"]}"#, as: StartReply.self)
        #expect(install.started && install.keys == ["ffmpeg", "ffprobe"])
        let use = try reply(#"{"ffmpeg":{"path":"/opt/homebrew/bin/ffmpeg","version":"8.0"},"custom":"/opt/homebrew/bin/ffmpeg"}"#,
                            as: ToolsUseReply.self)
        #expect(use.custom == "/opt/homebrew/bin/ffmpeg")
    }

    @Test func otherReplies() throws {
        let lists = try reply(#"{"ignore":{"path":"/s/ignore.txt","count":12},"corrections":{"path":"/s/corrections.txt","count":4}}"#,
                              as: ListsStatus.self)
        #expect(lists.ignore.count == 12 && lists.corrections.path == "/s/corrections.txt")
        let probe = try reply(#"""
            {"videos":[{"path":"/v/a.mkv","duration":1440.5,"fps":23.976,"width":1920,"height":1080},
                       {"path":"/v/b.mkv","error":"probe_failed","message":"no video stream or duration"}]}
            """#, as: VideosProbeReply.self)
        #expect(probe.videos[0].fps == 23.976 && probe.videos[1].error == "probe_failed" && probe.videos[1].duration == nil)
        #expect(try reply(#"{"out_path":"/v/a-fixed-20261113.srt","count":118}"#, as: SrtFixReply.self).count == 118)
        #expect(try reply(#"{"ok":false,"reason":"no_batch"}"#, as: StopReply.self) == StopReply(ok: false, reason: "no_batch"))
        #expect(try event("ready", #"{"version":"2.0.0","protocol":1,"pid":42}"#)
                == .ready(EngineReady(version: "2.0.0", protocol: 1, pid: 42)))
        #expect(try event("engine.exited", #"{"status":-9}"#) == .engineExited(status: -9))
        #expect(try event("something.new", "{}") == .other(name: "something.new"))
        #expect(throws: (any Error).self) { try event("batch.step", #"{"idx":"zero"}"#) }
    }

    @Test func paramsMatchTheEngine() throws {
        // The keys of core.OcrParams but the two lists: an unknown one is `bad_params`.
        let keys: Set<String> = ["fps", "lang_hint", "bottom_keep_pct", "keep_w_pct", "top_band", "top_keep_pct",
                                 "top_keep_w_pct", "recognition_level", "min_confidence", "multi_variant",
                                 "skip_hamming", "refine_timing", "min_duration", "merge_gap", "wrap_width",
                                 "workers", "qc_report", "qc_gap_warn", "qc_conf_warn", "qc_agree_warn"]
        let p = OcrParams()
        #expect(Set(p.dictionary.keys) == keys)
        // Encoded with the engine's coder, the same keys and values.
        let json = try JSONSerialization.jsonObject(with: EngineCoding.encoder.encode(p)) as? [String: Any]
        #expect(Set(json?.keys ?? [:].keys) == keys)
        #expect(p.fps == 12 && p.bottomKeepPct == 28 && p.keepWPct == 96 && p.minConfidence == 0.30 && p.wrapWidth == 42)
        let fast = OcrParams.fast
        #expect(fast.fps == 6 && fast.skipHamming == 1 && !fast.topBand && !fast.refineTiming && !fast.multiVariant)
        #expect(try reply(String(decoding: EngineCoding.encoder.encode(fast), as: UTF8.self), as: OcrParams.self) == fast)
    }

    @Test func helloCompatibilityAndErrorCodes() throws {
        let h = try reply(#"{"engine":"subvision","version":"2.0.0","protocol":1}"#, as: EngineHello.self)
        #expect(h.isCompatible && EngineHello.timeout == .seconds(90))
        #expect(EngineError.remote(code: "bad_params", message: "x").remoteCode == "bad_params")
        #expect(EngineError.notRunning.remoteCode == nil)
        // The optional details of the error object, `data {field, reason}` of bad_params included.
        let info = RemoteErrorInfo(error: ["code": "bad_params", "message": "lang_hint: not supported", "detail": "d", "tool": "vision",
                                           "path": "/v/a.srt", "line": 214, "data": ["field": "lang_hint", "reason": "not supported"]])
        #expect(info == RemoteErrorInfo(detail: "d", tool: "vision", path: "/v/a.srt", line: 214, field: "lang_hint", reason: "not supported"))
        #expect(EngineError.remote(code: "bad_params", message: "x", info: info).remoteInfo?.field == "lang_hint")
        #expect(EngineError.remote(code: "busy", message: "x").remoteInfo == RemoteErrorInfo())
        #expect(EngineError.notRunning.remoteInfo == nil)
        // batch.file.failed with the fields of protocol 2.0 final: code, text, detail, log.
        let failed = try reply(#"{"idx":0,"error":"unknown (OCRError: boom)","at_step":"ocr:bottom","code":"unknown","text":"boom","detail":"OCRError: boom","log":"/v/a.log"}"#, as: BatchFileFailed.self)
        #expect(failed.code == "unknown" && failed.text == "boom" && failed.log == "/v/a.log" && failed.atStep == "ocr:bottom" && failed.line == nil)
    }
}
