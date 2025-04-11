#!/bin/bash

# --- CONFIGURATION FUNCTIONS ---

# Clean path: unescape spaces, strip surrounding quotes
clean_path() {
  local raw="$1"
  raw="${raw%\"}"
  raw="${raw#\"}"
  echo -e "${raw//\\ / }"
}

# Extract duration in whole seconds using ffprobe
get_duration() {
  ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" | cut -d'.' -f1
}

# Generate a safe filename (alphanumeric, underscore, dash)
sanitize_filename() {
  echo "$1" | tr -cd '[:alnum:] _-' | sed 's/ /_/g'
}

# Convert one image + one audio into a video with a progress bar
convert() {
  local image="$1"
  local audio="$2"
  local output_base="$3"
  local duration

  duration=$(get_duration "$audio")
  [ -z "$duration" ] || [ "$duration" -le 0 ] && echo "❌ Error: Can't determine duration for $audio" && return

  echo "🎧 Processing: $(basename "$audio")"

  stdbuf -oL ffmpeg -loop 1 -i "$image" -i "$audio" \
    -map 0:v -map 1:a -c:v libx264 -tune stillimage -crf 24 \
    -pix_fmt yuv420p -r 30/1.001 -x264-params keyint=600 \
    -vf "scale=-1:1080,pad=1920:ih:(ow-iw)/2" -c:a aac -ab 320k \
    -strict -2 -shortest -movflags +faststart \
    -y "${output_base}.mp4" 2>&1 | \
    while IFS= read -r line; do
      if [[ "$line" =~ time=([0-9:.]+) ]]; then
        time_str="${BASH_REMATCH[1]}"
        current_time=$(awk -F: '{
          split($3, sec, ".")
          print (3600 * $1) + (60 * $2) + sec[1]
        }' <<< "$time_str")

        percent=$((current_time * 100 / duration))
        percent=$((percent > 100 ? 100 : percent))

        bar_length=40
        filled=$((percent * bar_length / 100))
        empty=$((bar_length - filled))
        bar=$(printf "%${filled}s" | tr ' ' '#')$(printf "%${empty}s")
        printf "\r[%s] %3d%%" "$bar" "$percent"
      fi
    done

  echo -e "\n✅ Done: ${output_base}.mp4"
}

# --- MAIN PROGRAM ---

# Prompt for mode
echo "Select mode:"
echo "1. Single image + single audio"
echo "2. Single image + multiple audios"
read -rp "Enter choice [1 or 2]: " mode

# Get image input
read -rp "Drag your INPUT IMAGE here and press [Enter]: " raw_image
image_path=$(clean_path "$raw_image")

if [ ! -f "$image_path" ]; then
  echo "❌ Error: Image file not found at: $image_path"
  exit 1
fi

# --- SINGLE FILE MODE ---
if [[ "$mode" == "1" ]]; then
  read -rp "Drag your INPUT AUDIO here and press [Enter]: " raw_audio
  audio_path=$(clean_path "$raw_audio")

  if [ ! -f "$audio_path" ]; then
    echo "❌ Error: Audio file not found at: $audio_path"
    exit 1
  fi

  audio_filename="$(basename "$audio_path")"
  output_base=$(sanitize_filename "${audio_filename%.*}")
  convert "$image_path" "$audio_path" "$output_base"

# --- BULK MODE ---
elif [[ "$mode" == "2" ]]; then
  echo "👉 Drag in ALL your audio files here (as one chunk) then press [Enter]:"
  read -r raw_audio_line

  # Use regex-compatible split with space unescaping
  IFS=$'\n' read -d '' -r -a raw_paths < <(
    echo "$raw_audio_line" | grep -oE '(\\.|[^[:space:]])+' | sed 's/\\ / /g'
  )

  # Validate and clean file paths
  audio_files=()
  for raw_path in "${raw_paths[@]}"; do
    clean=$(echo "$raw_path" | sed 's/^"//;s/"$//' | xargs)
    if [[ -f "$clean" && "$clean" =~ \.(mp3|wav|m4a|aac)$ ]]; then
      audio_files+=("$clean")
    else
      echo "⚠️  Skipping invalid or unsupported file: $clean"
    fi
  done

  if [ "${#audio_files[@]}" -eq 0 ]; then
    echo "❌ No valid audio files found."
    exit 1
  fi

  # Convert each audio file using the shared image
  for audio_path in "${audio_files[@]}"; do
    audio_filename="$(basename "$audio_path")"
    output_base=$(sanitize_filename "${audio_filename%.*}")
    convert "$image_path" "$audio_path" "$output_base"
  done

else
  echo "❌ Invalid selection."
  exit 1
fi