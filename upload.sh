#!/usr/bin/env bash
#
# upload.sh — Synchronise website and/or Gemini capsule to remote server using rsync
#
set -euo pipefail

# ==============================================================================
# CONFIGURATION
# Default remote server settings (can be overridden via environment variables)
# ==============================================================================
REMOTE_HOST="${REMOTE_HOST:-peterprevos.com}"
REMOTE_USER="${REMOTE_USER:-peter}"
REMOTE_PORT="${REMOTE_PORT:-22}"

# Remote destination directories
REMOTE_WWW_DIR="/home/peter/web/peterprevos.com/public_html"
REMOTE_GMI_DIR="/home/peter/gemini/peterprevos.com"

# Local directories
LOCAL_WWW_DIR="www/"
LOCAL_GMI_DIR="gmi/"

# Files/directories to preserve on remote or ignore
EXCLUDES=(
    "--exclude=.well-known"
    "--exclude=.git*"
    "--exclude=.DS_Store"
    "--exclude=*~"
)

# ==============================================================================
# HELP & USAGE
# ==============================================================================
show_help() {
    cat <<EOF
Usage: $0 [TARGET] [OPTIONS]

Upload compiled static files to remote server using rsync over SSH.

TARGETS:
  -www           Upload only the HTML website ('www/').
  -gmi           Upload only the Gemini capsule ('gmi/').
  (default)      Upload both 'www' and 'gmi' sequentially.

OPTIONS:
  -n, --dry-run  Perform a trial run with no changes made (shows what would sync).
  -h, --help     Display this help message and exit.

CONFIGURATION (Environment Variables):
  REMOTE_HOST    Target server hostname or IP (default: $REMOTE_HOST)
  REMOTE_USER    SSH username (default: $REMOTE_USER)
  REMOTE_PORT    SSH port (default: $REMOTE_PORT)

EXAMPLES:
  $0 -n              Preview changes for both website and Gemini capsule
  $0 -www -n         Preview changes for HTML website only
  $0 -www            Upload HTML website to $REMOTE_WWW_DIR
  $0 -gmi            Upload Gemini capsule to $REMOTE_GMI_DIR
  $0                 Upload both sites
EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
DRY_RUN=false
TARGET=""

for arg in "$@"; do
    case "$arg" in
        -n|--dry-run)
            DRY_RUN=true
            ;;
        -www)
            TARGET="www"
            ;;
        -gmi)
            TARGET="gmi"
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

# ==============================================================================
# RSYNC FUNCTION
# ==============================================================================
sync_dir() {
    local label="$1"
    local local_dir="$2"
    local remote_dir="$3"

    if [ ! -d "$local_dir" ]; then
        echo "Error: Local directory '$local_dir' does not exist. Run ./publish.sh first." >&2
        exit 1
    fi

    # RSYNC FLAGS:
    #   -a : archive mode (recurse, preserve permissions, timestamps, symlinks)
    #   -v : verbose output
    #   -z : compress file data during transfer
    #   -h : human-readable numbers
    #   -P : show progress and allow resumption of interrupted transfers
    #   --delete : delete extraneous files from destination (keeps remote clean)
    #   --no-owner, --no-group : avoid remote chown/chgrp permission errors
    #   --no-perms : do not overwrite remote permissions/ACLs with local permissions
    #   --omit-dir-times (-O) : avoid permission errors modifying directory timestamps
    local rsync_cmd=(
        rsync
        -avzhP
        --delete
        --no-owner
        --no-group
        --no-perms
        --omit-dir-times
        -e "ssh -p $REMOTE_PORT"
        "${EXCLUDES[@]}"
    )

    if [ "$DRY_RUN" = true ]; then
        rsync_cmd+=("--dry-run")
        echo "=== [DRY RUN] Synchronising $label to $REMOTE_USER@$REMOTE_HOST:$remote_dir/ ==="
    else
        echo "=== Synchronising $label to $REMOTE_USER@$REMOTE_HOST:$remote_dir/ ==="
    fi

    # Notice trailing slash on local_dir: copies directory contents into remote_dir/
    "${rsync_cmd[@]}" "$local_dir" "$REMOTE_USER@$REMOTE_HOST:$remote_dir/"
    echo "✓ $label completed."
    echo ""
}

# ==============================================================================
# EXECUTION
# ==============================================================================
case "$TARGET" in
    www)
        sync_dir "Website (HTML)" "$LOCAL_WWW_DIR" "$REMOTE_WWW_DIR"
        ;;
    gmi)
        sync_dir "Gemini Capsule" "$LOCAL_GMI_DIR" "$REMOTE_GMI_DIR"
        ;;
    "")
        sync_dir "Website (HTML)" "$LOCAL_WWW_DIR" "$REMOTE_WWW_DIR"
        sync_dir "Gemini Capsule" "$LOCAL_GMI_DIR" "$REMOTE_GMI_DIR"
        ;;
esac
