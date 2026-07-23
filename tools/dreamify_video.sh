#!/usr/bin/env bash
#
# Make a smooth, pre-slowed Klonk wallpaper with FFmpeg.
#
# The cheap observation phase prints a manifest and predicts duration/size before
# the expensive encode begins. Nothing is written until the user confirms (or
# --yes is supplied). The finished file is probed again to detect silent failure.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tools/dreamify_video.sh [options] INPUT [OUTPUT]

Options:
  --factor N       Slowdown factor (default: 4, equivalent to Klonk 0.25×)
  --mode MODE      blend (softer/faster) or flow (sharper/much slower)
  --height PX      Output height, preserving aspect ratio (default: 1440)
  --fps N          Output frame rate (default: 30)
  --bitrate RATE   HEVC target bitrate (default: 6M)
  --start SECONDS  Start at this source time (default: 0)
  --duration SEC   Use only this many source seconds
  --dry-run        Print the manifest and FFmpeg command, then stop
  --yes            Skip the confirmation prompt
  -h, --help       Show this help

Examples:
  # Recommended: turn a 15-minute excerpt into a one-hour dreamy loop.
  tools/dreamify_video.sh --start 600 --duration 900 nasa.mp4

  # Higher-quality motion estimation; expect a much longer encode.
  tools/dreamify_video.sh --mode flow --duration 60 nasa.mp4 test-flow.mp4

The output is already slowed while remaining 30 fps. Play it at Normal speed in
Klonk. Merely changing a 30 fps file's header to 120 fps does not create motion.
EOF
}

FACTOR=4
MODE=blend
HEIGHT=1440
OUTPUT_FPS=30
BITRATE=6M
START=0
DURATION=
DRY_RUN=0
YES=0
INPUT=
OUTPUT=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --factor)   [[ $# -ge 2 ]] || { echo "Missing value for --factor" >&2; exit 2; }; FACTOR=$2; shift 2 ;;
    --mode)     [[ $# -ge 2 ]] || { echo "Missing value for --mode" >&2; exit 2; }; MODE=$2; shift 2 ;;
    --height)   [[ $# -ge 2 ]] || { echo "Missing value for --height" >&2; exit 2; }; HEIGHT=$2; shift 2 ;;
    --fps)      [[ $# -ge 2 ]] || { echo "Missing value for --fps" >&2; exit 2; }; OUTPUT_FPS=$2; shift 2 ;;
    --bitrate)  [[ $# -ge 2 ]] || { echo "Missing value for --bitrate" >&2; exit 2; }; BITRATE=$2; shift 2 ;;
    --start)    [[ $# -ge 2 ]] || { echo "Missing value for --start" >&2; exit 2; }; START=$2; shift 2 ;;
    --duration) [[ $# -ge 2 ]] || { echo "Missing value for --duration" >&2; exit 2; }; DURATION=$2; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --yes)      YES=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    --)         shift; break ;;
    -*)         echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -z "$INPUT" ]]; then INPUT=$1
      elif [[ -z "$OUTPUT" ]]; then OUTPUT=$1
      else echo "Unexpected argument: $1" >&2; usage >&2; exit 2
      fi
      shift
      ;;
  esac
done

while [[ $# -gt 0 ]]; do
  if [[ -z "$INPUT" ]]; then INPUT=$1
  elif [[ -z "$OUTPUT" ]]; then OUTPUT=$1
  else echo "Unexpected argument: $1" >&2; usage >&2; exit 2
  fi
  shift
done

[[ -n "$INPUT" ]] || { usage >&2; exit 2; }
[[ -f "$INPUT" ]] || { echo "Input is not a file: $INPUT" >&2; exit 2; }
[[ "$MODE" == "blend" || "$MODE" == "flow" ]] || {
  echo "--mode must be blend or flow" >&2; exit 2
}

for tool in ffmpeg ffprobe awk; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required command: $tool" >&2; exit 2
  }
done

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${INPUT%.*}-dreamy-${FACTOR}x.mp4"
fi
[[ "$OUTPUT" != "$INPUT" ]] || { echo "Output must differ from input" >&2; exit 2; }
[[ ! -e "$OUTPUT" ]] || { echo "Refusing to overwrite existing output: $OUTPUT" >&2; exit 2; }

number_gt_zero() { awk -v n="$1" 'BEGIN { exit !(n + 0 > 0) }'; }
number_at_least_zero() { awk -v n="$1" 'BEGIN { exit !(n + 0 >= 0) }'; }
number_gt_zero "$FACTOR" || { echo "--factor must be positive" >&2; exit 2; }
number_gt_zero "$HEIGHT" || { echo "--height must be positive" >&2; exit 2; }
number_gt_zero "$OUTPUT_FPS" || { echo "--fps must be positive" >&2; exit 2; }
number_at_least_zero "$START" || { echo "--start must not be negative" >&2; exit 2; }
if [[ -n "$DURATION" ]]; then
  number_gt_zero "$DURATION" || { echo "--duration must be positive" >&2; exit 2; }
fi

SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT")
SOURCE_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT")
SOURCE_SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
  -of csv=p=0:s=x "$INPUT")
SOURCE_FPS_EXPR=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
  -of default=noprint_wrappers=1:nokey=1 "$INPUT")
SOURCE_FPS=$(awk -F/ -v r="$SOURCE_FPS_EXPR" \
  'BEGIN { split(r,a,"/"); if (a[2] == 0) print 0; else printf "%.3f", a[1]/a[2] }')

AVAILABLE_DURATION=$(awk -v total="$SOURCE_DURATION" -v start="$START" \
  'BEGIN { d=total-start; if (d < 0) d=0; printf "%.3f", d }')
number_gt_zero "$AVAILABLE_DURATION" || {
  echo "--start is beyond the end of the source" >&2; exit 2
}
if [[ -z "$DURATION" ]]; then
  CLIP_DURATION=$AVAILABLE_DURATION
else
  CLIP_DURATION=$(awk -v requested="$DURATION" -v available="$AVAILABLE_DURATION" \
    'BEGIN { d=requested < available ? requested : available; printf "%.3f", d }')
fi

EXPECTED_DURATION=$(awk -v d="$CLIP_DURATION" -v factor="$FACTOR" \
  'BEGIN { printf "%.3f", d*factor }')
INTERPOLATION_FPS=$(awk -v fps="$OUTPUT_FPS" -v factor="$FACTOR" \
  'BEGIN { printf "%.3f", fps*factor }')
BITRATE_BPS=$(awk -v rate="$BITRATE" 'BEGIN {
  suffix=substr(rate,length(rate),1); value=rate+0; multiplier=1;
  if (suffix=="k" || suffix=="K") multiplier=1000;
  if (suffix=="m" || suffix=="M") multiplier=1000000;
  if (suffix=="g" || suffix=="G") multiplier=1000000000;
  printf "%.0f", value*multiplier
}')
EXPECTED_BYTES=$(awk -v seconds="$EXPECTED_DURATION" -v bps="$BITRATE_BPS" \
  'BEGIN { printf "%.0f", seconds*bps/8 }')
EXPECTED_GIB=$(awk -v bytes="$EXPECTED_BYTES" \
  'BEGIN { printf "%.2f", bytes/1073741824 }')

if [[ "$MODE" == "blend" ]]; then
  INTERPOLATOR="minterpolate=fps=${INTERPOLATION_FPS}:mi_mode=blend"
  STRATEGY="frame blending; soothing/fast, with possible soft ghosting"
  CONFIDENCE="high cadence; medium artifact-free"
else
  INTERPOLATOR="minterpolate=fps=${INTERPOLATION_FPS}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
  STRATEGY="motion-compensated optical flow; sharper/much slower, with possible edge warping"
  CONFIDENCE="high cadence; medium artifact-free"
fi
FILTER="scale=-2:${HEIGHT}:flags=lanczos,${INTERPOLATOR},setpts=${FACTOR}*(PTS-STARTPTS),fps=${OUTPUT_FPS}"

FFMPEG_ARGS=(-hide_banner -n -nostdin -ss "$START")
if [[ -n "$DURATION" ]]; then FFMPEG_ARGS+=(-t "$CLIP_DURATION"); fi
FFMPEG_ARGS+=(
  -i "$INPUT"
  -map 0:v:0
  -vf "$FILTER"
  -an
  -c:v hevc_videotoolbox
  -tag:v hvc1
  -b:v "$BITRATE"
  -pix_fmt yuv420p
  -movflags +faststart
  "$OUTPUT"
)

echo "EVENT observe.complete"
echo "MANIFEST"
printf '  input:              %s\n' "$INPUT"
printf '  source:             %s, %s, %s fps, %.1f minutes\n' \
  "$SOURCE_CODEC" "$SOURCE_SIZE" "$SOURCE_FPS" "$(awk -v d="$SOURCE_DURATION" 'BEGIN { print d/60 }')"
printf '  selected range:     %.1f–%.1f minutes (%.1f source minutes)\n' \
  "$(awk -v s="$START" 'BEGIN { print s/60 }')" \
  "$(awk -v s="$START" -v d="$CLIP_DURATION" 'BEGIN { print (s+d)/60 }')" \
  "$(awk -v d="$CLIP_DURATION" 'BEGIN { print d/60 }')"
printf '  strategy:           %s\n' "$STRATEGY"
printf '  interpolation:      %s fps before %sx slowdown\n' "$INTERPOLATION_FPS" "$FACTOR"
printf '  output:             %s\n' "$OUTPUT"
printf '  predicted result:   %sp, %s fps, %.1f minutes, approximately %s GiB\n' \
  "$HEIGHT" "$OUTPUT_FPS" "$(awk -v d="$EXPECTED_DURATION" 'BEGIN { print d/60 }')" "$EXPECTED_GIB"
printf '  confidence:         %s\n' "$CONFIDENCE"
echo "  success criteria:   output probes cleanly; expected height/fps/duration"
echo
printf 'COMMAND\n  '
printf '%q ' ffmpeg "${FFMPEG_ARGS[@]}"
echo

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "EVENT plan.finish status=dry-run"
  exit 0
fi

if [[ "$YES" -ne 1 ]]; then
  echo
  printf 'Begin this potentially long encode? [y/N] '
  read -r REPLY
  [[ "$REPLY" == "y" || "$REPLY" == "Y" ]] || {
    echo "EVENT encode.finish status=cancelled"
    exit 0
  }
fi

ENCODE_STARTED=1
on_exit() {
  status=$?
  if [[ "${ENCODE_STARTED:-0}" -eq 1 && "$status" -ne 0 ]]; then
    echo "EVENT encode.finish status=failed exit=$status failure_class=ffmpeg-or-verification" >&2
    echo "A partial output may remain at: $OUTPUT" >&2
  fi
}
trap on_exit EXIT

echo "EVENT encode.start"
ffmpeg "${FFMPEG_ARGS[@]}"
ENCODE_STARTED=0

ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")
ACTUAL_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")
ACTUAL_FPS_EXPR=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
  -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")
ACTUAL_FPS=$(awk -F/ -v r="$ACTUAL_FPS_EXPR" \
  'BEGIN { split(r,a,"/"); if (a[2] == 0) print 0; else printf "%.3f", a[1]/a[2] }')
ACTUAL_BYTES=$(wc -c < "$OUTPUT" | tr -d ' ')

DURATION_OK=$(awk -v actual="$ACTUAL_DURATION" -v expected="$EXPECTED_DURATION" \
  'BEGIN { tolerance=expected*0.01; if (tolerance < 2) tolerance=2;
           print ((actual-expected < tolerance) && (expected-actual < tolerance)) ? 1 : 0 }')
FPS_OK=$(awk -v actual="$ACTUAL_FPS" -v expected="$OUTPUT_FPS" \
  'BEGIN { print ((actual-expected < 0.1) && (expected-actual < 0.1)) ? 1 : 0 }')
HEIGHT_OK=$([[ "$ACTUAL_HEIGHT" == "$HEIGHT" ]] && echo 1 || echo 0)

echo "EVENT verify.finish duration_ok=$DURATION_OK fps_ok=$FPS_OK height_ok=$HEIGHT_OK"
printf 'RESULT\n  duration: %.3f seconds\n  dimensions: height %s\n  frame rate: %s fps\n  size: %.2f GiB\n' \
  "$ACTUAL_DURATION" "$ACTUAL_HEIGHT" "$ACTUAL_FPS" \
  "$(awk -v bytes="$ACTUAL_BYTES" 'BEGIN { print bytes/1073741824 }')"

if [[ "$DURATION_OK" != 1 || "$FPS_OK" != 1 || "$HEIGHT_OK" != 1 ]]; then
  echo "EVENT encode.finish status=failed failure_class=output-drift" >&2
  exit 3
fi

echo "EVENT encode.finish status=succeeded"
