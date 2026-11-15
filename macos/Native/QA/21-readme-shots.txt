# The README images of 2.0 (design/immagini-readme-2.0.md): the real window,
# captured alone by `screencapture -l` (window-shot), at 1360 × 860, from a real
# batch on the Sintel demo clips (CC-BY Blender Foundation). The clips sit in a
# neutral work folder, "~/Movies/SubVision demo" on screen (display-home: the
# scenario's own folder stands in for the home). A third video is a renamed copy.
# Only the failed file of the end-of-batch sheet is fed by hand (engine-event).
# Every image in both appearances (the READMEs show the one of the reader's GitHub theme).
# The PNGs land in $OUT; the WebPs are made from them by hand (cwebp, see the list),
# parameters_* cut from parameters-window_* (noshadow): 712 x 1440 px at 2008,106.
@state base
! mkdir -p "home/Movies/SubVision demo"
! cd "home/Movies/SubVision demo" && cp "$DEMO/sintel_ita_hardsub_demo.mp4" "$DEMO/sintel_eng_hardsub_demo.mp4" . && cp "$DEMO/sintel_ita_hardsub_demo.mp4" sintel_cartelli_demo.mp4
# The third video has an SRT already (E10: «SRT già presente»)
! cp "$REF/sintel_ita_hardsub_demo.srt" "home/Movies/SubVision demo/sintel_cartelli_demo.srt"
@launch
wait-ready 600
? ^ready
settings-feed clear
# The demo clips are Italian: Italian is the default subtitle language here, so no value shows as changed
sublang it-IT
? it-IT
display-home $WORK/home
? /home$
lang it
size 1360x860
window-size
? ^1360x860 
params default
inspector-set langHint it-IT
inspector-tab read
theme dark
tab process
add $WORK/home/Movies/SubVision demo/sintel_ita_hardsub_demo.mp4,$WORK/home/Movies/SubVision demo/sintel_eng_hardsub_demo.mp4,$WORK/home/Movies/SubVision demo/sintel_cartelli_demo.mp4
checks
? ^header on · sintel_ita_hardsub_demo\.mp4=on sintel_eng_hardsub_demo\.mp4=on sintel_cartelli_demo\.mp4=on$
# A first batch of the first two: the third stays out
check 2
? sintel_cartelli_demo\.mp4=off$
start
? status ready
wait-batch 900
? ^batch done · done 2 failed 0
summary-seen
# 5 · video_rows (E10): before a batch, the done row open, the one to do open with its frames
check 2
? sintel_cartelli_demo\.mp4=on$
drawer 0 open
drawer 2 open
? ^open sintel_ita_hardsub_demo\.mp4 sintel_cartelli_demo\.mp4$
wait-strips 120
? sintel_cartelli_demo\.mp4=video:5
bottom-bar
? ^checked 1 · finished 2
! sleep 1
window-shot $OUT/video_rows_dark_it.png
? png$
lang en
! sleep 1
window-shot $OUT/video_rows_dark_en.png
? png$
theme light
! sleep 1
window-shot $OUT/video_rows_light_en.png
? png$
lang it
! sleep 1
window-shot $OUT/video_rows_light_it.png
? png$
theme dark
# 8 · preview (A3): the Preview of the first video on the first frame with text, Try OCR,
# then the signs band changed: its panel goes out of date. (The demo clips have no signs:
# the Signs panel reads nothing.)
preview-open 0
? ^ok · sintel_ita_hardsub_demo\.mp4
wait-frames 300
? ^20 frames
try-ocr
wait-ocr 120
inspector-tab bands
inspector-set ocr.topKeepPct 26
preview-state
? stale
! sleep 1
window-shot $OUT/preview_dark_it.png
? png$
lang en
! sleep 1
window-shot $OUT/preview_dark_en.png
? png$
theme light
! sleep 1
window-shot $OUT/preview_light_en.png
? png$
lang it
! sleep 1
window-shot $OUT/preview_light_it.png
? png$
theme dark
lang en
preview-close
? ^ok
# 7 · parameters (I2): the panel on Bands with one value changed, light; cut from the window
# (back on Video the panel shows the page's own tab again)
inspector-tab bands
theme light
! sleep 1
window-shot $OUT/parameters-window_light_en.png noshadow
? png$
lang it
! sleep 1
window-shot $OUT/parameters-window_light_it.png noshadow
? png$
theme dark
! sleep 1
window-shot $OUT/parameters-window_dark_it.png noshadow
? png$
lang en
! sleep 1
window-shot $OUT/parameters-window_dark_en.png noshadow
? png$
lang it
inspector-set ocr.topKeepPct 22
theme dark
inspector-tab read
# 9 · review (R1): the first video's report in the Review page (before the second batch,
# whose SRTs get the date in their names)
tab review
review 0
? Revisione di sintel_ita_hardsub_demo\.mp4
! sleep 2
window-shot $OUT/review_dark_it.png
? png$
lang en
! sleep 2
window-shot $OUT/review_dark_en.png
? png$
theme light
! sleep 2
window-shot $OUT/review_light_en.png
? png$
lang it
! sleep 2
window-shot $OUT/review_light_it.png
? png$
theme dark
report-close
lang it
# 10 · subfix (F2): the first video's SRT fixed
tab fix
fix-open $WORK/home/Movies/SubVision demo/sintel_ita_hardsub_demo.srt
fix-run
wait-fix 60
fix-state
! sleep 1
window-shot $OUT/subfix_dark_it.png
? png$
lang en
! sleep 1
window-shot $OUT/subfix_dark_en.png
? png$
theme light
! sleep 1
window-shot $OUT/subfix_light_en.png
? png$
lang it
! sleep 1
window-shot $OUT/subfix_light_it.png
? png$
theme dark
# Back to Italian before the batch shots (the next two are the _it ones)
lang it
tab process
# 3, 4 · video (E2): a batch of the three, the first done, the second in its OCR, the third waiting
drawer 0 close
drawer 2 close
? ^open -$
! rm "home/Movies/SubVision demo/sintel_cartelli_demo.srt"
process-again 0,1
checks
? sintel_ita_hardsub_demo\.mp4=redo sintel_eng_hardsub_demo\.mp4=redo sintel_cartelli_demo\.mp4=on$
start
? status ready
wait-step 1 ocr 600
? ^ok
# The second row open (the first one's drawer, opened by itself, keeps the second closed)
drawer 0 close
drawer 1 open
? ^open sintel_eng_hardsub_demo\.mp4$
! sleep 9
window-shot $OUT/video_dark_it.png
? png$
theme light
window-shot $OUT/video_light_it.png
? png$
lang en
window-shot $OUT/video_light_en.png
? png$
theme dark
window-shot $OUT/video_dark_en.png
? png$
batch-bar
lang it
# 6 · video_finished (E6): the third file stopped as it starts, then said failed (by hand)
wait-step 2 extract 600
? ^ok
stop-file 2
wait-batch 300
? ^batch done
engine-event batch.file.failed {"idx":2,"error":"vision_unavailable (VisionError: request failed)","at_step":"ocr:bottom","code":"vision_unavailable","text":"","detail":"VisionError: request failed","log":"$WORK/home/Movies/SubVision demo/sintel_cartelli_demo.log"}
summary-sheet
? 2 SRT pronti · 1 non riuscito
drawer 1 close
! sleep 1
window-shot $OUT/video_finished_dark_it.png
? png$
lang en
! sleep 1
window-shot $OUT/video_finished_dark_en.png
? png$
theme light
! sleep 1
window-shot $OUT/video_finished_light_en.png
? png$
lang it
! sleep 1
window-shot $OUT/video_finished_light_it.png
? png$
theme dark
summary-seen
lang it
tab process
display-home off
theme system
params default
inspector-tab read
sublang clear
