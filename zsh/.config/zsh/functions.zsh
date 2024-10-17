function brew() {
  if [[ $1 == "add" ]]; then
    # Remove the first argument ("add")
    shift
    # Install the package
    command brew install "$@"
    # Update the global Brewfile
    command brew bundle dump --global --force
  else
    # Call the original brew command with all original arguments
    command brew "$@"
  fi
}

function ffm_compress() {
  if [ $# -ne 1 ]; then
      echo "Usage: ffm_compress <input_video_path>"
      return 1
  fi

  input_path="$1"
  # Get the filename without extension
  filename=$(basename -- "$input_path")
  filename_noext="${filename%.*}"

  # Create output filename in same directory as input
  output_path="${filename_noext}.mp4"

  ffmpeg -i "$input_path" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k "$output_path"
}