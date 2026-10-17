# peterprevos.com Website and Gemini Capsule Publishing Engine

This repository contains the custom Emacs Org mode publishing pipeline for [peterprevos.com](https://peterprevos.com) and its twin Gemini capsule (`gemini://peterprevos.com`).

A series of three articles on [Publishing Websites with Emacs and Org Mode](https://peterprevos.com/praxis/publishing-websites-with-org-mode-01-principles/) explains how to build websites with Emacs Org mode.

## Directory Structure

```text
├── publish.sh            # Main CLI build runner
├── publish-common.el     # Shared macros and functions
├── publish-www.el        # HTML export
├── publish-gmi.el        # Gemini export
├── content/              # Org source files
│   └── images/           # Image assets
├── static-www/           # Web static assets
├── static-gmi/           # Gemini static assets
├── www/                  # Compiled HTML website
└── gmi/                  # Compiled Gemini capsule
```

## Custom Functionality

This publishing system extends standard Org mode export (`ox-publish`, `ox-html`, and `ox-gemini`) with bespoke subsystems.

### 1. Unified environment and offline batch execution
* Consolidated package activation (`publish-common.el`): Package sources and local paths
* Hermetic Invocation (`publish.sh`): Runs Emacs in batch mode, independent of the personal configuration.

### 2. Content lifecycle and file embargo
* Draft and embargo filtering (`ews-org-publish-exclude-regex`) excludes:
  * Files containing `#+draft: t`
  * Files with future dates (`#+date: <YYYY-MM-DD>`)
* Shared metadata parsing (`ews-org-get-page-meta`):
  * Extracts author name and publication date
  * Computes estimated reading time at 200 words per minute.

### 3. Org macros
* `{{{list-files}}}` generates semi-automated category pages
  * It calls `ews-org-publish-list-files` to dynamically render a list of articles with links and descriptions.
* `{{{youtube(id, caption)}}}` embeds player in HTML or a hyperlink in LaTeX / Gemtext.
* `{{{youtube-playlist(id, caption)}}}` same for YouTube playlists.
* `{{{backend}}}` results in either "website" or "Gemini capsule", depending on the export backend

### 4. Pretty URLs & Link Rewriting
* Pretty URLs (`ews-org-publish-to-pretty-html`):
  * Compiles `category/article.org` into `category/article/index.html` (except for `/index.org` and `/404.org`).
* Root-relative link and image filter (`ews-org-html-pretty-link-filter`):
  * Operates on `:filter-link` to rewrite relative `.html` links into root-relative pretty URLs.
  * Intercepts `<img>` tags and rewrites relative image paths (`../images/...`) to root-relative `/images/...`.

### 5. Technical SEO (`publish-www.el`)
* Dynamic Open Graph, Twitter cards (`ews-org-html-open-graph-tags`):
  * Generates canonical URLs, Open Graph properties, and Twitter summary cards.
  * Uses either article or website template, depending `#options: article:t`.
* Structured Data (JSON-LD):
  * Generates `BlogPosting` schema on articles and `WebSite` schema on root pages.
  * Injects `BreadcrumbList` schema (`Home > Section > Article`) for Google SERP rich snippet navigation.
* Cross-Protocol Discovery:
  * Injects `<link rel="alternate" type="text/gemini" href="gemini://peterprevos.com/..." />` into the HTML `<head>` for Gemini-aware browsers.
* XML sitemap (`ews-org-publish-generate-sitemap-xml`):
  * Evaluates during `:completion-function` after HTML publishing.
  * Resolves pretty subdirectories back to source `.org` files, reading `#+date:` or `#+lastmod:` values.
  * Assigns priority (`1.0` for root, `0.8` for section hubs, `0.7` for articles).
* `LLMs.txt` file for AI agents (`ews-org-publish-generate-llms-txt`):
  * Evaluates during `:preparation-function`.
  * Generates a curated Markdown index of published articles for LLM agents.

### 6. Gemini Capsule Optimizations (`publish-gmi.el`)
The `ox-gemini` package has been enhanced to allow for better rendering. Ideally some of theses should be incorporated upstream into he package.

* Heading Level Offset (`ews-gemini-build-title`):
  * Overrides `org-gemini--build-title` to shift headline levels down by one, preserving level 1 for the page title.
  * Maximises 3 levels to Gemtext specification.
* Native Image Detection (`ews-gemini-image-link-p`):
  * Uses Emacs 29+ `image-supported-file-p` to recognise images
* Inline Image Figures (`org-gemini-link`:
  * Adds canonical Gemtext link lines (`=> /images/photo.jpg Caption`) directly in the reading flow, using `#+caption:` as the description
* Section-end links (`ews-gemini-describe-links`):
  * Aggregates hyperlinks at the bottom of each section.
  * Rewrites `.org` (and `.org::*heading`) links to `.gmi`.
  * Emits bare links without fake fallback labels (`=> URL`).
* Paragraph sanitisation (`ews-gemini-paragraph`):
  * Trims trailing whitespace bugs present in upstream `ox-gemini`.
* Emphasis delimiter suppression:
  * Configures `:with-emphasize t` to strip emphasise markers in Gemtext.
* Export snippet support (`ews-gemini-export-snippet`):
  * Transcodes `@@gemini:...@@`, `@@gmi:...@@`, and `@@gemtext:...@@` export snippets (e.g. inside `#+macro:`), which are omitted by upstream `ox-gemini`.
* Chronological Gemlog Feed (`ews-gemini-sitemap-builder`):
  * Outputs a flat, capsule-wide reverse-chronological feed (`gemlog.gmi`) for Gemini feed readers.
* Atomic colophon injection (`ews-gemini-final-output-filter`):
  * Appends a static colophon to the end of each `gmi` file.

### 7. Editorial Workflow & Org-agenda Integration
* Publishing Schedule Completion Function (`ews-org-publish-generate-publishing-schedule`):
  * Evaluates after HTML publishing to generate `publishing-schedule.org` in the project root.
  * Collects all draft and future-embargoed articles excluded from publishing.
  * Articles with scheduled publication dates are assigned the `TODO` keyword with an Org deadline.
  * Articles without a date are assigned the `NEXT` keyword.
  * Reuses the generated table of contents to append a `* Published` section listing all live articles.
  * Can be appended to `org-agenda-files`

## Building the Capsule & Website

The build script `publish.sh` manages compilation:

```bash
# Incremental build of both Web and Gemini targets (fast)
./publish.sh

# Incremental build including drafts and future posts
./publish.sh -d

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
