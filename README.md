# peterprevos.com Website and Gemini Capsule Publishing Engine

This repository contains the custom Emacs Org mode publishing pipeline for [peterprevos.com](https://peterprevos.com) and its twin Gemini capsule (`gemini://peterprevos.com`).

A series of three articles on [Publishing Websites with Emacs and Org Mode](https://peterprevos.com/praxis/publishing-websites-with-org-mode-01-principles/) explains how to build websites with Emacs Org mode in great detail.

## Directory Structure

```text
├── publish.sh            # Bash build script 
├── upload.sh             # rsync website and capsule over SSH
├── social-card-generator.sh # Generate custom social cards from template
├── publish-common.el     # Shared macros and functions
├── publish-www.el        # HTML export
├── publish-gmi.el        # Gemini export
├── templates/            # HTML templates and source stylesheet
│   ├── head.html         # Document <head> markup
│   ├── preamble.html     # Header navigation menu
│   ├── postamble.html    # Footer markup and licensing
│   └── custom.css        # Source CSS modifications for peterprevos.com
├── content/              # Org source files and static assets
│   ├── images/           # Images
│   ├── static-www/       # Web static assets
│   └── static-gmi/       # Gemini static assets
├── www/                  # Compiled HTML website
└── gmi/                  # Compiled Gemini capsule
```

## Custom Functionality

This publishing system extends standard Org mode export (`ox-publish`, `ox-html`, and `ox-gemini`) with several bespoke functions.

### 1. Batch execution
* Hermetic Invocation (`publish.sh`): Runs Emacs in batch mode, independent of the personal configuration.
  * Fetches the latest upstream SimpleCSS (`simple.min.css`) and caches it in `.packages/`.
  * Minifies site overrides in `templates/custom.css` (stripping comments, whitespace, and redundant syntax).
  * Concatenates SimpleCSS with the minified custom CSS into `content/static-www/custom.css`.
  * Eliminates external CDN dependencies and loads a single self-hosted stylesheet.
* Dynamic Base Directory Resolution (`ews-org-publish-base-dir`):
  * Resolves the content directory dynamically from `:base-directory` in `org-publish-project-alist`.
  * Uses `locate-dominating-file` to reliably anchor the root, eliminating hardcoded directory names across publishing functions, feed generators, filters, and macros.

### 2. Content lifecycle and file embargo
* Draft and embargo filtering (`ews-org-publish-exclude-regex`) excludes:
  * Files containing `#+draft: t`
  * Files with future dates (`#+date: <YYYY-MM-DD>`)
  * `#+options: www:nil`: Excludes a file from the HTML website output.
  * `#+options: gmi:nil`: Excludes a file from the Gemini capsule output.
* Draft inclusion flag (`./publish.sh -d`):
  * Sets `ews-drafts` to `t`, publishing embargoed, draft, and future-dated articles.
* Shared metadata parsing (`ews-org-get-page-meta`):
  * Extracts author name and publication date.
  * Computes estimated reading time at 200 words per minute.
  * Injects author name, date, word count, and reading time as subtitle on articles (`:article t`). Non-article pages (e.g. index, TOC, and hub pages) disable this via `#+options: article:nil`.

### 3. Org macros
* `{{{list-files}}}` generates category pages:
  * Calls `ews-org-publish-list-files` to dynamically render a list of articles with links and descriptions.
  * Prepends date to the title by default, or the `#+order:` string when sorted by order, followed by the description.
  * Accepts an optional argument, e.g. `{{{list-files(order)}}}`, to sort ascending by each file's `#+order:` string (e.g. `"01"`, `"02"`, `"01-03"`). Unordered articles follow at the end sorted by date.
  * **Freshness Guarantee (`html-always`)**: Because Org mode caches file modification timestamps, category hub pages (`logos/index.org`, `praxis/index.org`, etc.) would otherwise be skipped during incremental builds when new articles are added. `publish-www.el` defines an `"html-always"` project that forces re-exporting all category index pages on every run (`(org-publish "html-always" t)`), guaranteeing that dynamic article listings stay up to date without requiring a slow full site rebuild (`-rw`).
* `{{{atom-feeds}}}` generates an HTML list of category Atom feeds:
  * Calls `ews-org-publish-atom-feeds` using `ews-org-publish-category-dirs` to discover categories.
  * Formats links with `@@html:@@` export snippets for the HTML backend (e.g. on `/toc/#feeds`).
* `{{{youtube(id, caption)}}}` embeds a responsive player with `<figure>` and `<figcaption>` in HTML, or a hyperlink in LaTeX / Gemtext.
* `{{{youtube-playlist(id, caption)}}}` embeds YouTube playlists with responsive layout and captions across backends.
* `{{{backend}}}` results in "website", "Gemini capsule", or "document", depending on the active export backend.

### 4. Pretty URLs & Link Rewriting
* Pretty URLs (`ews-org-publish-to-pretty-html`):
  * Converts `category/article.org` into `category/article/index.html` (except `/index.org` and `/404.org`).
* Root-relative link and image filter (`ews-org-html-pretty-link-filter`):
  * Operates on `:filter-link` to rewrite relative `.html` links into root-relative pretty URLs.
  * Intercepts `<img>` tags and rewrites relative image paths (`../images/...`) to root-relative `/images/...`.

### 5. Technical SEO & Web Feeds (`publish-www.el`)
* Dynamic Open Graph, Twitter cards (`ews-org-html-open-graph-tags`):
  * Generates canonical URLs, Open Graph properties, and Twitter summary cards.
  * Uses either article (`BlogPosting`) or website template, depending on `:article` (defaults to `t`, disabled via `#+options: article:nil`).
  * Cascading social card resolution:
    1. Explicit `#+image:` keyword defined in the article.
    2. Auto-generated per-page card (`images/${slug}.png`) if present in `content/images/`.
    3. Global fallback to `:default-social-card-image` (`images/default-social-card-image.png`).
  * If no `#+image:` is specified and no card exists on disk, image meta tags (`og:image`, `twitter:image`) are cleanly omitted and Twitter cards switch to standard `summary`.
* Category Atom Feeds (`webfeeder` & `ews-org-publish-generate-category-feeds`):
  * Generates an Atom feed (`atom.xml`) for each category subdirectory in `content/` (`/logos/`, `/praxis/`, etc.) during `:completion-function`.
  * Preserves article publication dates (`#+date:`) and pretty URL slugs.
  * Injects `<link rel="alternate" type="application/atom+xml" ...>` discovery links in the `<head>` of category hubs and articles.
  * Embedded into the Table of Contents via the `{{{atom-feeds}}}` macro.
  * Dynamically populates the site footer (`templates/postamble.html`) with a contextual Atom link pointing to the category's feed on article pages or `/toc/#feeds` on root pages.
* Structured Data (JSON-LD):
  * Generates `BlogPosting` schema on articles and `WebSite` schema on root pages.
  * Injects `BreadcrumbList` schema (`Home > Section > Article`) for Google SERP rich snippet navigation.
* Cross-Protocol Discovery:
  * Injects `<link rel="alternate" type="text/gemini" href="gemini://peterprevos.com/..." />` into the HTML `<head>` for Gemini-aware browsers.
* XML sitemap (`ews-org-publish-generate-sitemap-xml`):
  * Generates standard `sitemap.xml` directly from compiled HTML files in `www/`.
  * Assigns crawling priority and change frequency based on URL structure without requiring Org source inspection.
* `llms.txt` [file for AI agents](https://llmstxt.org/) (`ews-org-publish-generate-llms-txt`):
  * A markdown summary to help large language models (LLMs) better understand the content on the site. 
  * Evaluates during `:preparation-function`.

### 6. Gemini Capsule Optimizations (`publish-gmi.el`)
The `ox-gemini` package has been enhanced to allow for better rendering. Ideally some of these should be incorporated upstream into the package.

* Preformatted Example Blocks (`ews-gemini-example-block`):
  * Transcodes `#+begin_example` blocks to standard Gemtext preformatted toggles (```), preserving ASCII diagrams and verbatim text alignment.
* Heading Level Offset (`ews-gemini-build-title`):
  * Overrides `org-gemini--build-title` to shift headline levels down by one, preserving level 1 for the page title.
  * Maximises 3 levels to Gemtext specification.
* Native Image Detection (`ews-gemini-image-link-p`):
  * Uses Emacs 29+ `image-supported-file-p` to recognise images.
* Inline Image Figures (`org-gemini-link`):
  * Adds canonical Gemtext link lines (`=> /images/photo.jpg Caption`) directly in the reading flow, using `#+caption:` as the description.
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
  * Reuses the generated table of contents to append a `* Published` section listing all live articles with full absolute filesystem paths.
  * Can be appended to `org-agenda-files` with full link navigation support from agenda views.

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

# Clean, complete rebuild of website only
./publish.sh -www -rw
```

## Generating Social Sharing Cards

The automation script `social-card-generator.sh` creates custom Open Graph cards (1200 × 630) for each page:
* Parses titles from compiled HTML files in `www/`.
* Composites wrapped typography over `content/images/social/default-social-card-image.png`.
* Saves each card as a unique file in `content/images/social/${slug}.png` (which `publish.sh` automatically publishes to `www/images/social/`).
* Automatically skips custom illustrations (e.g. photos defined via `#+image:`) to avoid overwriting them.
* Incremental generation: skips images that are already newer than their corresponding HTML file.

```bash
# Generate cards for all compiled pages in www/
./social-card-generator.sh
```

## Uploading to Remote Server

The deployment script `upload.sh` synchronises compiled files using `rsync` over SSH:
* Uses `--no-perms`, `--no-owner`, and `--no-group` to safely preserve server-side file ownership, group memberships, and POSIX ACL masks.
* Protects remote server assets (e.g. `.well-known`, `.git*`, `cgi-bin`) from deletion during sync.
* Supports dry-run previews (`-n`).

```bash
# Preview what would be uploaded to both Web and Gemini targets (dry run)
./upload.sh -n

# Preview website upload only
./upload.sh -www -n

# Upload website to /home/peter/web/peterprevos.com/public_html
./upload.sh -www

# Upload Gemini capsule to /home/peter/gemini/peterprevos.com
./upload.sh -gmi

# Upload both targets
./upload.sh
```

Note: The code for this website was developed with the assistance of AI and manually refactored.
