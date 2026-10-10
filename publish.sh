#!/bin/sh
#
# publish.sh — Build script for peterprevos.com website and Gemini capsule
#
# This script orchestrates static site generation using Emacs Org mode in batch mode.
# It can compile the World Wide Web (HTML) version, the Gemini capsule, or both.
#
# USAGE:
#   ./publish.sh [TARGET] [OPTIONS]
#
# TARGETS:
#   -www         Publish the World Wide Web (HTML) site into 'www/'.
#   -gmi         Publish the Gemini capsule (Gemtext) into 'gmi/'.
#   (none)       If no target is given, both targets are published.
#
# OPTIONS:
#   -rw          Rewrite mode. Deletes the output directory ('www/' or 'gmi/')
#                and forces a complete rebuild of all files.
#                Without this flag, Org mode performs a fast incremental build,
#                skipping unchanged files based on timestamp cache.
#   -h, --help   Show usage information.
#
# EXAMPLES:
#   ./publish.sh            # Incremental build of both Web and Gemini sites
#   ./publish.sh -www       # Incremental build of HTML website only
#   ./publish.sh -gmi -rw   # Full, clean rebuild of Gemini capsule
#   ./publish.sh -rw        # Full, clean rebuild of both sites
#

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
  -h, --help   Display this help message and exit.

EXAMPLES:
  $0               Incremental build of both Web and Gemini sites
  $0 -www          Incremental build of HTML website only
  $0 -gmi -rw      Clean rebuild of Gemini capsule from scratch
  $0 -rw           Clean rebuild of both Web and Gemini sites
EOF
}

rw_val="nil"
target=""

# Parse command line flags
for arg in "$@"; do
    case "$arg" in
        -rw)
            rw_val="t"
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

publish_www() {
    if [ "$rw_val" = "t" ]; then
        rm -rf www
    fi
    emacs -Q --batch \
        --eval "(setq ews-rw $rw_val)" \
        --load publish-www.el \
        --eval '(ews-publish)'
}

publish_gmi() {
    if [ "$rw_val" = "t" ]; then
        rm -rf gmi
    fi
    emacs -Q --batch \
        --eval "(setq ews-rw $rw_val)" \
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
