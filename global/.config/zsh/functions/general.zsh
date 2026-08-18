function ffm_compress() {
  if [ $# -ne 1 ]; then
    echo 'Usage: ffm_compress <input_video_path>'
    return 1
  fi

  input_path="$1"
  filename=$(basename -- "$input_path")
  filename_noext="${filename%.*}"
  output_path="${filename_noext}.mp4"

  if [ "$input_path" = "$output_path" ]; then
    echo "Output will be ${filename_noext}_out.mp4"
    output_path="${filename_noext}_out.mp4"
  fi

  ffmpeg -i "$input_path" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k "$output_path"
}
