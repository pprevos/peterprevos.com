#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
SITE_DIR="${1:-www}"                   # Root directory containing compiled HTML files
DEST_DIR="${2:-content/images/social}" # Destination directory for generated cards
BG_IMAGE="${BG_IMAGE:-content/images/social/default-social-card-image.png}" # Template background image
FONT="DejaVu-Sans"                     # Font family name or path to .ttf/.otf
TEXT_COLOR="#FFFFFF"                   # Font color (Hex or named color)
BOX_WIDTH=1000                         # Max text bounding box width (pixels)
BOX_HEIGHT=360                         # Max text bounding box height (pixels)
FONT_SIZE=48                           # Base font pointsize (0 for auto-fit)

# ==============================================================================
# DEPENDENCY CHECKS
# ==============================================================================
if command -v magick &>/dev/null; then
    IM_CMD="magick"
elif command -v convert &>/dev/null; then
    IM_CMD="convert"
else
    echo "Error: ImageMagick ('magick' or 'convert') is required." >&2
    exit 1
fi

if [[ ! -f "$BG_IMAGE" ]]; then
    echo "Error: Background image '$BG_IMAGE' not found." >&2
    exit 1
fi

mkdir -p "$DEST_DIR"

# ==============================================================================
# MAIN PROCESSING LOOP
# ==============================================================================
echo "Searching for HTML files in '$SITE_DIR'..."

find "$SITE_DIR" -type f \( -name "*.html" -o -name "*.htm" \) | while read -r html_file; do
    # Extract relative path from SITE_DIR
    rel_path="${html_file#$SITE_DIR/}"
    rel_path="${rel_path#./}"

    # Skip 404 error pages
    if [[ "$rel_path" == "404.html" || "$rel_path" == "404/index.html" ]]; then
        continue
    fi

    # Determine unique image slug based on HTML path
    if [[ "$rel_path" == "index.html" ]]; then
        slug="index"
    elif [[ "$rel_path" == */index.html ]]; then
        dir_path="${rel_path%/index.html}"
        slug="${dir_path##*/}"
    else
        slug="$(basename "$rel_path" | sed 's/\.[^.]*$//')"
    fi

    # Extract og:image or twitter:image content from <head>
    img_rel_path=$(perl -0777 -ne '
        if (/<meta\s+(?:property|name)=["\x27](?:og:image|twitter:image)["\x27]\s+content=["\x27]([^"\x27]+)["\x27]/is) {
            print $1;
        } elsif (/"image"\s*:\s*["\x27]([^"\x27]+)["\x27]/is) {
            print $1;
        }
    ' "$html_file")

    # If the HTML explicitly specifies a custom photo/image that is not the default
    # background or the auto-generated card, skip it to protect manual illustrations
    if [[ -n "$img_rel_path" ]]; then
        img_name="${img_rel_path##*/}"
        if [[ "$img_name" != "default-social-card-image.png" && "$img_name" != "${slug}.png" ]]; then
            echo "Skipping (has custom illustration): $html_file -> $img_name"
            continue
        fi
    fi

    # Extract og:title or <title>, decode basic HTML entities, clean whitespace
    title=$(perl -0777 -ne '
        my $t = "";
        if (/<meta\s+property=["\x27]og:title["\x27]\s+content=["\x27]([^"\x27]+)["\x27]/is) {
            $t = $1;
        } elsif (/<title[^>]*>(.*?)<\/title>/is) {
            $t = $1;
        }
        $t =~ s/&amp;/&/g;
        $t =~ s/&#39;/\x27/g;
        $t =~ s/&quot;/"/g;
        $t =~ s/&lt;/</g;
        $t =~ s/&gt;/>/g;
        $t =~ s/\s+/ /g;
        $t =~ s/^\s+|\s+$//g;
        print $t;
    ' "$html_file")

    # Fallback title if missing
    if [[ -z "$title" ]]; then
        title="$slug"
    fi

    out_file="$DEST_DIR/${slug}.png"

    # Skip if output image already exists and is newer than the HTML file
    if [[ -f "$out_file" && "$out_file" -nt "$html_file" ]]; then
        echo "Up to date: $out_file"
        continue
    fi

    echo "Generating: $out_file"
    echo "  └─ Title: \"$title\""

    # Set pointsize argument if specified
    FONT_ARG=()
    if [[ "$FONT_SIZE" -gt 0 ]]; then
        FONT_ARG=(-pointsize "$FONT_SIZE")
    fi

    # Render wrapped text layer via ImageMagick caption: and composite over background
    "$IM_CMD" "$BG_IMAGE" \
        \( -background transparent \
           -fill "$TEXT_COLOR" \
           -font "$FONT" \
           "${FONT_ARG[@]}" \
           -size "${BOX_WIDTH}x${BOX_HEIGHT}" \
           -gravity Center \
           caption:"$title" \) \
        -gravity Center -composite "$out_file"

done

echo "Processing complete."