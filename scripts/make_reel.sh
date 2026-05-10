#!/usr/bin/env bash
# Build a 9:16 Instagram Reel (mp4) for 大嵓埜 monthly course.
# Output: dist/reel.mp4
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
SRCS="$BUILD/srcs"
CLIPS="$BUILD/clips"
TITLES="$BUILD/titles"
DIST="$ROOT/dist"
mkdir -p "$SRCS" "$CLIPS" "$DIST"

# 1) Stage Japanese-named source images under ASCII names so the rest of the
#    pipeline can reference them without quoting headaches. Filenames on disk
#    use NFD-decomposed kana (ジ = シ + dakuten), so we resolve via globs.
copy_glob () {
  local pat="$1" dst="$2"
  local matches=( $pat )
  if [ ! -f "${matches[0]}" ]; then
    echo "no match for: $pat" >&2; exit 1
  fi
  cp -f "${matches[0]}" "$SRCS/$dst"
}
copy_glob "*_*0008.jpg" "chouri_a.jpg"  # landscape, 調理0008
copy_glob "*_*0010.jpg" "chouri_b.jpg"  # portrait,  調理0010
copy_glob "*_*0049.jpg" "chouri_c.jpg"  # landscape, 調理0049
copy_glob "*_*0054.jpg" "chouri_d.jpg"  # portrait,  調理0054
copy_glob "造里0008.jpg" "zukuri_a.jpg"
copy_glob "造里0020.jpg" "zukuri_b.jpg"
copy_glob "造里0039.jpg" "zukuri_c.jpg"
copy_glob "*QR*.png"     "qr.png"

W=1080; H=1920; FPS=30

# Ken Burns clip generator. Each clip is rendered to 1080x1920@30fps,
# CFR, with a luxury color grade and brand+vignette overlay baked in.
# Args: <input> <out> <duration_sec> <zoom_dir: in|out|panL|panR|panU|panD>
make_clip () {
  local IN="$1" OUT="$2" DUR="$3" MODE="$4"
  local FRAMES
  FRAMES=$(awk -v d="$DUR" -v f="$FPS" 'BEGIN{printf "%d", d*f}')
  local PRE_W=2160 PRE_H=3840          # 2x oversample for the zoompan
  local Z_EXPR X_EXPR Y_EXPR
  case "$MODE" in
    in)    Z_EXPR="1.0+0.18*on/${FRAMES}";              X_EXPR="iw/2-(iw/zoom/2)"; Y_EXPR="ih/2-(ih/zoom/2)";;
    out)   Z_EXPR="1.18-0.18*on/${FRAMES}";             X_EXPR="iw/2-(iw/zoom/2)"; Y_EXPR="ih/2-(ih/zoom/2)";;
    panL)  Z_EXPR="1.10";                               X_EXPR="(iw-iw/zoom)*(1-on/${FRAMES})"; Y_EXPR="ih/2-(ih/zoom/2)";;
    panR)  Z_EXPR="1.10";                               X_EXPR="(iw-iw/zoom)*(on/${FRAMES})";   Y_EXPR="ih/2-(ih/zoom/2)";;
    panU)  Z_EXPR="1.10";                               X_EXPR="iw/2-(iw/zoom/2)"; Y_EXPR="(ih-ih/zoom)*(1-on/${FRAMES})";;
    panD)  Z_EXPR="1.10";                               X_EXPR="iw/2-(iw/zoom/2)"; Y_EXPR="(ih-ih/zoom)*(on/${FRAMES})";;
  esac

  # Note: zoompan d=1 (one output frame per input frame) avoids the well-known
  # ffmpeg pitfall where d=N multiplies the frame count for every input frame
  # in a `-loop 1 -t DUR` stream. We drive timing with input framerate + -t.
  ffmpeg -y -loglevel error \
    -loop 1 -framerate ${FPS} -t "$DUR" -i "$IN" \
    -loop 1 -framerate ${FPS} -t "$DUR" -i "$TITLES/vignette.png" \
    -loop 1 -framerate ${FPS} -t "$DUR" -i "$TITLES/brand.png" \
    -filter_complex "
      [0:v]scale=${PRE_W}:${PRE_H}:force_original_aspect_ratio=increase,
           crop=${PRE_W}:${PRE_H},setsar=1,
           zoompan=z='${Z_EXPR}':x='${X_EXPR}':y='${Y_EXPR}':d=1:s=${W}x${H}:fps=${FPS},
           eq=contrast=1.06:saturation=0.88:brightness=-0.02:gamma=0.98,
           curves=preset=increase_contrast,
           vignette=PI/5[v0];
      [v0][1:v]overlay=0:0[v1];
      [v1][2:v]overlay=0:0,format=yuv420p[v]
    " \
    -map "[v]" -t "$DUR" -r ${FPS} -c:v libx264 -preset medium -crf 19 \
    -pix_fmt yuv420p -movflags +faststart "$OUT"
}

# Title / caption / outro clips: build from a black canvas + overlay PNG.
make_text_clip () {
  local OVERLAY="$1" OUT="$2" DUR="$3" FADE_IN="${4:-0.6}" FADE_OUT="${5:-0.6}"
  local FADE_OUT_START
  FADE_OUT_START=$(awk -v d="$DUR" -v f="$FADE_OUT" 'BEGIN{printf "%.3f", d-f}')
  ffmpeg -y -loglevel error \
    -f lavfi -t "$DUR" -i "color=c=0x0a0a0a:s=${W}x${H}:r=${FPS}" \
    -loop 1 -t "$DUR" -i "$OVERLAY" \
    -i "$TITLES/vignette.png" \
    -i "$TITLES/brand.png" \
    -filter_complex "
      [0:v]format=yuv420p,
        geq=lum='lum(X,Y)+12*sin(2*PI*Y/H + T*0.6)':cb='cb(X,Y)':cr='cr(X,Y)'[bg];
      [bg][1:v]overlay=0:0[t1];
      [t1][2:v]overlay=0:0[t2];
      [t2][3:v]overlay=0:0,
        fade=t=in:st=0:d=${FADE_IN},
        fade=t=out:st=${FADE_OUT_START}:d=${FADE_OUT},
        format=yuv420p[v]
    " \
    -map "[v]" -r ${FPS} -c:v libx264 -preset medium -crf 19 \
    -pix_fmt yuv420p -movflags +faststart "$OUT"
}

# QR closing card: white-ish background to make QR scannable.
make_outro_clip () {
  local DUR="$1" OUT="$2"
  ffmpeg -y -loglevel error \
    -f lavfi -t "$DUR" -i "color=c=0x0d0d0d:s=${W}x${H}:r=${FPS}" \
    -loop 1 -t "$DUR" -i "$SRCS/qr.png" \
    -loop 1 -t "$DUR" -i "$TITLES/99_outro.png" \
    -loop 1 -t "$DUR" -i "$TITLES/brand.png" \
    -filter_complex "
      [1:v]scale=720:-1[qr];
      [0:v][qr]overlay=(W-w)/2:(H-h)/2+60[bgqr];
      [bgqr][2:v]overlay=0:0[bgqrt];
      [bgqrt][3:v]overlay=0:0,
        fade=t=in:st=0:d=0.6,
        format=yuv420p[v]
    " \
    -map "[v]" -r ${FPS} -c:v libx264 -preset medium -crf 19 \
    -pix_fmt yuv420p -movflags +faststart "$OUT"
}

echo ">> rendering clips"
# 各カット +2秒。テロップ「仕込み」「旬の鮮魚を…」「造里」のシーンは削除。
make_text_clip "$TITLES/01_title.png"      "$CLIPS/01_title.mp4"   5.0 0.8 0.8
make_clip      "$SRCS/chouri_a.jpg"        "$CLIPS/02_chouri_a.mp4" 4.6 in
make_clip      "$SRCS/chouri_b.jpg"        "$CLIPS/03_chouri_b.mp4" 4.6 panU
make_clip      "$SRCS/chouri_c.jpg"        "$CLIPS/05_chouri_c.mp4" 4.6 panR
make_clip      "$SRCS/chouri_d.jpg"        "$CLIPS/06_chouri_d.mp4" 4.6 in
make_clip      "$SRCS/zukuri_a.jpg"        "$CLIPS/09_zukuri_a.mp4" 4.6 in
make_clip      "$SRCS/zukuri_b.jpg"        "$CLIPS/10_zukuri_b.mp4" 4.6 out
make_clip      "$SRCS/zukuri_c.jpg"        "$CLIPS/11_zukuri_c.mp4" 4.6 panD
make_outro_clip 6.0                        "$CLIPS/12_outro.mp4"

# Concat list
LIST="$BUILD/concat.txt"
: > "$LIST"
for f in 01_title 02_chouri_a 03_chouri_b 05_chouri_c 06_chouri_d \
         09_zukuri_a 10_zukuri_b 11_zukuri_c 12_outro; do
  echo "file '$CLIPS/${f}.mp4'" >> "$LIST"
done

echo ">> concatenating video"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" \
  -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p -r ${FPS} \
  -movflags +faststart "$BUILD/video_only.mp4"

# ---------- Audio ----------
# Total duration of video for trimming the BGM
TOTAL=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$BUILD/video_only.mp4")
echo ">> video duration: ${TOTAL}s; building BGM"

# Use the repository's MP3 as BGM, looped to the video length with fade in/out.
BGM_SRC="$ROOT/Porcelain_and_Pine.mp3"
FADE_OUT_START=$(awk -v t="$TOTAL" 'BEGIN{printf "%.3f", t-1.5}')
ffmpeg -y -loglevel error \
  -stream_loop -1 -i "$BGM_SRC" \
  -filter_complex "
    [0:a]aresample=48000,
         volume=0.85,
         afade=t=in:st=0:d=1.2,
         afade=t=out:st=${FADE_OUT_START}:d=1.5
  " \
  -t "$TOTAL" -ac 2 -c:a aac -b:a 192k "$BUILD/bgm.m4a"

echo ">> muxing"
ffmpeg -y -loglevel error \
  -i "$BUILD/video_only.mp4" -i "$BUILD/bgm.m4a" \
  -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest \
  -movflags +faststart "$DIST/reel.mp4"

echo ">> done: $DIST/reel.mp4"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,duration \
  -of default=nw=1 "$DIST/reel.mp4"
