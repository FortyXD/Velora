#!/usr/bin/env bash
# Today's picture from Bing, NASA's astronomy picture of the day or Wikimedia's picture of the day,
# saved to ~/Pictures/Wallpapers/Daily and applied. Prints the saved path.
# usage: wallpaper_of_the_day.sh <bing|nasa|wikimedia> [keep-days] [--no-apply]
# NASA_KEY may hold an api.nasa.gov key (DEMO_KEY otherwise).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
NOTIFY_TITLE="Wallpaper of the day"

source_name=${1:-bing}
keep_days=${2:-14}
apply=1
[[ ${3:-} == --no-apply ]] && apply=0
dir="$(get_pictures_dir)/Wallpapers/Daily"
mkdir -p -- "$dir" || fail "Cannot create $dir."
today=$(date +%F)

case $source_name in
    bing)
        json=$(api_get "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=ru-RU")
        base=$(jq -r '.images[0].urlbase // empty' <<< "$json")
        [[ -n "$base" ]] || fail "Bing returned no picture."
        url="https://www.bing.com${base}_UHD.jpg"
        title=$(jq -r '.images[0].copyright // ""' <<< "$json")
        page=$(jq -r '.images[0].copyrightlink // "https://www.bing.com"' <<< "$json")
        ;;
    nasa)
        # Some days are videos; go back a few days to the latest picture
        for days_back in 0 1 2 3 4 5; do
            day=$(date -d "-$days_back day" +%F)
            json=$(api_get "https://api.nasa.gov/planetary/apod?api_key=${NASA_KEY:-DEMO_KEY}&date=$day")
            if [[ $(jq -r '.media_type // ""' <<< "$json") == image ]]; then
                url=$(jq -r '.hdurl // .url' <<< "$json")
                title=$(jq -r '.title // ""' <<< "$json")
                page="https://apod.nasa.gov/apod/ap$(date -d "$day" +%y%m%d).html"
                break
            fi
        done
        [[ -n "${url:-}" ]] || fail "NASA had no picture in the last days."
        ;;
    wikimedia)
        json=$(api_get "https://api.wikimedia.org/feed/v1/wikipedia/en/featured/$(date +%Y/%m/%d)")
        url=$(jq -r '.image.image.source // empty' <<< "$json")
        [[ -n "$url" ]] || fail "Wikimedia had no picture of the day."
        title=$(jq -r '.image.description.text // .image.title // ""' <<< "$json" | sed 's/<[^>]*>//g')
        page=$(jq -r '.image.file_page // "https://commons.wikimedia.org"' <<< "$json")
        ;;
    *)
        fail "Unknown source: $source_name"
        ;;
esac

ext="${url##*.}"
ext="${ext%%\?*}"
[[ "$ext" =~ ^(jpe?g|png|webp)$ ]] || ext=jpg
dest="$dir/$today-$source_name.$ext"
if [[ ! -f "$dest" ]]; then
    notify_progress "$NOTIFY_TITLE" "Downloading…"
    fetch_image "$url" "$dest"
fi
jq -n --arg source "$source_name" --arg title "$title" --arg page "$page" --arg url "$url" \
    '{source: $source, title: $title, page: $page, url: $url}' > "${dest%.*}.json"

# Older pictures go, except the one in use
current=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null)
find "$dir" -type f -mtime "+$keep_days" ! -path "$current" ! -path "${current%.*}.json" -delete 2>/dev/null

if [[ $apply -eq 1 ]]; then
    apply_wallpaper "$dest"
fi
echo "$dest"
