# The first-launch image of the READMEs (design/immagini-readme-2.0.md, row 2) in the light
# appearance: the real window, captured alone by `screencapture -l` (window-shot), in the state
# of the dark one (T1: uv + Python done, FFmpeg at 12 of 28 MB, "Downloading 2 of 3 · 63 of
# 107 MB · about 2 minutes left"), fed by hand over a ready app (a real download is over in
# seconds, too fast to catch at that point).
@launch
wait-ready 600
? ^ready
lang en
theme light
tools-feed start
? ^window · 2 of 3 · 51 of 107 MB$
# The time left comes from the bytes since FFmpeg started: 12 MB in 28 s, 44 MB to go
! sleep 28
tools-feed 12
? ^window · 2 of 3 · 63 of 107 MB$
! sleep 1
window-shot $OUT/first_launch_light_en.png
? png$
lang it
! sleep 1
window-shot $OUT/first_launch_light_it.png
? png$
theme system
