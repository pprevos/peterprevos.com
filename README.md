# peterprevos.com Website and Gemini Capsule Publishing Engine

This repository contains the custom Emacs Org mode publishing pipeline for [peterprevos.com](https://peterprevos.com) and its twin Gemini capsule (`gemini://peterprevos.com`).

This series of three articles on [Publishing Websites with Emacs and Org Mode](https://peterprevos.com/praxis/publishing-websites-with-org-mode-01-principles/) explains how to build websites with Emacs Org mode.

## Architecture & Directory Structure

```text
├── publish.sh            # Main CLI build runner (batch Emacs)
├── publish-common.el     # Shared macros, filters, metadata extractors, and sitemaps
├── publish-www.el        # HTML export configuration, Open Graph, and JSON-LD
├── publish-gmi.el        # Gemini export configuration and Gemtext AST transcoders
├── content/              # Single source of truth for all articles and pages (.org)
│   └── images/           # Shared image assets (.jpg, .png, .svg)
├── static-www/           # Web-only static assets
├── static-gmi/           # Gemini-only static assets
├── www/                  # Compiled production HTML website
└── gmi/                  # Compiled production Gemini capsule
```

## Non-Standard & Custom Functionality

This publishing system extends standard Org mode export (`ox-publish`, `ox-html`, and `ox-gemini`) with bespoke subsystems.

### 1. Unified environment and offline batch execution
* Consolidated package activation (`publish-common.el`): Package sources and local paths are configured in one place.
* Hermetic Invocation (`publish.sh`): Runs Emacs in batch mode, independent of the personal configuration.

### 2. Content lifecycle and file embargo
* draft and embargo filtering (`ews-org-publish-exclude-regex`) excludes:
  * Files containing `#+draft: t`
  * Files with future dates (`#+date: <YYYY-MM-DD>`)
* Shared metadata parsing (`ews-org-get-page-meta`):
  * Calculates buffer word counts (excluding drawers, comments, and keywords).
  * Computes estimated reading time at 200 words per minute.
  * Standardises author and publication dates across both HTML and Gemini.

### 3. Automated content listings macro 
* The `{{{list-files}}}` macro can generate semi-automated category pages
* Depending on the active backend, it calls `ews-org-publish-list-files` to dynamically render a list of articles with links and descriptions.

### 4. Pretty URLs & Link Rewriting (`publish-common.el`)
* Pretty URLs (`ews-org-publish-to-pretty-html`):
  * Compiles `category/article.org` into `category/article/index.html` (except for `index.org` and `404.org`).
* Root-relative link and image filter (`ews-org-html-pretty-link-filter`):
  * Operates on `:filter-link` to rewrite relative `.html` links into root-relative pretty URLs.
  * Intercepts `<img>` tags and rewrites relative image paths (`../images/...`) to root-relative `/images/...`, resolving path-depth breakage caused by subfolder relocation.

### 5. Technical SEO and rich snippets (`publish-www.el`)
* Dynamic Open Graph and Twitter cards (`ews-org-html-open-graph-tags`):
  * Automatically generates canonical URLs, Open Graph properties, and Twitter summary cards.
* Structured Data (JSON-LD):
  * Generates `BlogPosting` schema on articles and `WebSite` schema on root pages.
  * Injects `BreadcrumbList` schema (`Home > Section > Article`) for Google SERP rich snippet navigation.
* Cross-Protocol Discovery:
  * Injects `<link rel="alternate" type="text/gemini" href="gemini://peterprevos.com/..." />` into the HTML `<head>` for Gemini-aware browsers.
* Compliant XML sitemap (`ews-org-publish-generate-sitemap-xml`):
  * Evaluates during `:completion-function` after HTML publishing.
  * Resolves pretty subdirectories back to source `.org` files, reading `#+date:` or `#+lastmod:` values.
  * Assigns priority (`1.0` for root, `0.8` for section hubs, `0.7` for articles).
* `LLMs.txt` file for AI agents (`ews-org-publish-generate-llms-txt`):
  * Evaluates during `:preparation-function`.
  * Generates a curated Markdown index of published articles for LLM agents.

### 6. Gemini Capsule Optimizations (`publish-gmi.el`)
The `ox-gemini` package has been enhanced to allow for better rendering. Ideally some of theses should be incorporated into the package.

* Heading Level Offset (`ews-gemini-build-title`):
  * Overrides `org-gemini--build-title` to shift headline levels down by one, preserving level 1 for the page title.
  * Maximises 3 levels at to strictly Gemtext specification.
* Native Image Detection (`ews-gemini-image-link-p`):
  * Uses Emacs 29+ `image-supported-file-p` to recognise images
* Inline Image Figures (`org-gemini-link`:
  * Emits canonical Gemtext link lines (`=> /images/photo.jpg Caption`) directly in the reading flow, resolving `#+caption:` and URL-encoding paths.
* Section-end links (`ews-gemini-describe-links`):
  * Aggregates hyperlinks at the bottom of each section.
  * Rewrites `.org` (and `.org::*heading`) links to `.gmi`.
  * Emits bare links without fake fallback labels (`=> URL`).
* Paragraph sanitisation (`ews-gemini-paragraph`):
  * Trims trailing whitespace bugs present in upstream `ox-gemini`.
* Emphasis delimiter suppression:
  * Configures `:with-emphasize t` with custom transcoders to strip `/` and `*` delimiters, producing clean natural prose in Gemtext.
* Chronological Gemlog Feed (`ews-gemini-sitemap-builder`):
  * Outputs a flat, capsule-wide reverse-chronological feed (`gemlog.gmi`) formatted for Gemini feed readers.
* Atomic colophon injection (`ews-gemini-final-output-filter`):
  * Appends the colophon during export, eliminating post-build file-rewrite loops.

## Building the Capsule & Website

The build script `publish.sh` manages compilation:

```bash
# Incremental build of both Web and Gemini targets (fast)
./publish.sh

# Incremental build of website only
./publish.sh -www

# Incremental build of Gemini capsule only
./publish.sh -gmi

# Clean, complete rebuild of both targets from scratch
./publish.sh -rw

# Clean, complete rebuild of Gemini capsule only
./publish.sh -gmi -rw

# Clean, complete rebuild of website  only
./publish.sh -www -rw
```
