#!/bin/sh
#
# publish.sh — Build script for peterprevos.com website and Gemini capsule
#
# This script orchestrates static site generation using Emacs Org mode in batch mode.
# It can compile the World Wide Web (HTML) version, the Gemini capsule, or both.

show_help() {
    cat <<EOF
Usage: $0 [TARGET] [OPTIONS]

Publish the website and/or Gemini capsule using Emacs Org mode.

TARGETS:
  -www         Publish only the World Wide Web (HTML) site into 'www/'.
  -gmi         Publish only the Gemini capsule (Gemtext) into 'gmi/'.
  (default)    Publish both 'www' and 'gmi' sequentially.

OPTIONS:
  -rw          Rewrite mode: delete output folder ('www/' or 'gmi/') and
               force a full rebuild of all files. Without this flag, an
               incremental build is performed, skipping unmodified files.
  -d           Include drafts and future-dated posts in the published output.
  -h, --help   Display this help message and exit.

EXAMPLES:
  $0               Incremental build of both Web and Gemini sites
  $0 -www          Incremental build of HTML website only
  $0 -gmi -rw      Clean rebuild of Gemini capsule from scratch
  $0 -d            Build both sites including drafts and future posts
  $0 -rw           Clean rebuild of both Web and Gemini sites
EOF
}

rw_val="nil"
drafts_val="nil"
target=""

# Parse command line flags
for arg in "$@"; do
    case "$arg" in
        -rw)
            rw_val="t"
            ;;
        -d)
            drafts_val="t"
            ;;
        -www)
            target="www"
            ;;
        -gmi)
            target="gmi"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$arg'" >&2
            echo "" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Navigate to the script's directory for robust execution
cd "$(dirname "$0")" || exit 1

minify_css() {
    if command -v perl >/dev/null 2>&1; then
        perl -0777 -pe '
            s{/\*.*?\*/}{}gs;
            s{\s+}{ }g;
            s{\s*([;{}:,>])\s*}{$1}g;
            s{;(?=\})}{}g;
            s{^\s+|\s+$}{}g;
        '
    else
        cat
    fi
}

build_css() {
    SIMPLE_CSS_URL="https://cdn.simplecss.org/simple.min.css"
    CACHE_DIR=".packages"
    CACHE_FILE="$CACHE_DIR/simple.min.css"
    DEST_DIR="content/static-www"
    DEST_FILE="$DEST_DIR/custom.css"
    CUSTOM_SRC="templates/custom.css"

    mkdir -p "$CACHE_DIR" "$DEST_DIR"

    echo "Fetching latest SimpleCSS from $SIMPLE_CSS_URL..."
    if wget -q --timeout=15 -O "$CACHE_FILE.tmp" "$SIMPLE_CSS_URL"; then
        mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    else
        echo "Failed to download SimpleCSS. Using cached copy if available." >&2
        rm -f "$CACHE_FILE.tmp"
    fi

    if [ ! -f "$CACHE_FILE" ]; then
        echo "Error: SimpleCSS could not be downloaded and no cached copy found at $CACHE_FILE." >&2
        exit 1
    fi

    echo "Bundling and minifying SimpleCSS with $CUSTOM_SRC -> $DEST_FILE..."
    {
        cat "$CACHE_FILE"
        echo ""
        minify_css < "$CUSTOM_SRC"
        echo ""
    } > "$DEST_FILE"
}

publish_www() {
    build_css
    if [ "$rw_val" = "t" ]; then
        rm -rf www
    fi
    emacs -Q --batch \
        --eval "(setq ews-rw $rw_val)" \
        --eval "(setq ews-drafts $drafts_val)" \
        --load publish-www.el \
        --eval '(ews-publish)'
}

publish_gmi() {
    if [ "$rw_val" = "t" ]; then
        rm -rf gmi
    fi
    emacs -Q --batch \
        --eval "(setq ews-rw $rw_val)" \
        --eval "(setq ews-drafts $drafts_val)" \
        --load publish-gmi.el \
        --eval '(ews-publish)'
}

case "$target" in
    www)
        publish_www
        ;;
    gmi)
        publish_gmi
        ;;
    "")
        publish_www
        publish_gmi
        ;;
esac
