;;; publish-gmi.el --- Publishing peterprevos.com Gemini Capsule -*- lexical-binding: t; -*-

;;; Commentary:
;; Build script for Gemini capsule generation using Org mode.

;;; Code:

;; Load shared publishing definitions and package environment
(add-to-list 'load-path (file-name-directory (expand-file-name (or load-file-name buffer-file-name "."))))
(require 'publish-common)

;; Load packages
(require 'ox-publish)
(require 'ox-gemini)
(require 'image)

;; Strip emphasis markers (Gemtext has no inline bold/italics syntax)
(let ((backend (org-export-get-backend 'gemini)))
  (setf (org-export-backend-transcoders backend)
        (append '((italic . (lambda (_i contents _info) contents))
                  (bold . (lambda (_b contents _info) contents))
                  (underline . (lambda (_u contents _info) contents))
                  (strike-through . (lambda (_s contents _info) contents))
                  (verbatim . (lambda (v _c _info)
                                (format "`%s`" (org-element-property :value v))))
                  (code . (lambda (c _c _info)
                            (format "`%s`" (string-trim (org-element-property :value c))))))
                (org-export-backend-transcoders backend))))

;; Updates to ox-gemini
(defun ews-gemini-build-title (element info _text-width &optional _underline _notags toc)
  "Format an Org headline ELEMENT as a Gemtext heading line.

ELEMENT is the headline AST node.
INFO is a plist holding export options and document state.
_TEXT-WIDTH, _UNDERLINE, and _NOTAGS are inherited from `ox-ascii' and unused.
TOC, when non-nil, indicates the title is being formatted for a table of
contents entry and prefers alternate titles (:alt-title).

Returns a Gemtext heading string where the heading level is offset by +1. Org
level 1 `*` becomes Gemtext `##`) and limited to 3."
  (let* ((level (min 3 (1+ (org-element-property :level element))))
         (title-data (if toc
                         (org-export-get-alt-title element info)
                       (org-element-property :title element)))
         (text (org-trim (org-export-data title-data info))))
    (format "%s %s" (make-string level ?#) text)))

(advice-add 'org-gemini--build-title :override #'ews-gemini-build-title)

(defcustom org-gemini-link-symbol '("" "")
  "Configure opening and closing indicators for links."
  :group 'org-export-gemini
  :type '(list string string))

(defun ews-gemini-image-link-p (link)
  "Return non-nil if LINK targets an image file and has no bracket description."
  (and (not (org-element-contents link))
       (let ((path (org-element-property :path link)))
         (and (org-string-nw-p path)
              (image-supported-file-p path)))))

(defun org-gemini-link (link desc info)
  "Transcode an Org LINK element into Gemtext.

LINK is the link AST node representing the Org hyperlink or image.
DESC is the transcoded description string if the link has explicit anchor
text (e.g. \"[[path][desc]]\"), or nil for bare links (e.g. \"[[path]]\").
INFO is a plist containing export options and document state.

This function overrides upstream `ox-gemini-link' with dual behavior:

1. Standalone Images / Media:
   If LINK points to an image file (tested via `ews-gemini-image-link-p'),
   it emits a canonical Gemtext link line (`=> URL LABEL`) directly into
   the document flow where the figure occurs. The LABEL is resolved in order
   of precedence:
     a. Explicit link description (DESC).
     b. Enclosing paragraph `#+caption:' keyword.
     c. File base name fallback.
   URLs are sanitized via `url-encode-url' so spaces do not truncate the link.

2. Inline Hyperlinks:
   For non-image links, Gemtext cannot embed hyperlinks inside running prose.
   Instead of forcing bracket delimiters (`[text]`), this function emits DESC
   wrapped with `org-gemini-link-symbol' (by default `(\"\" \"\")' for clean,
   unencumbered prose). The destination URL is collected and output at the end
   of the section by `ews-gemini-describe-links'.

Returns a Gemtext-formatted string."
  (let* ((raw-path (org-element-property :raw-link link))
         (path-val (org-element-property :path link))
         (link-type (org-element-property :type link))
         (is-file (string= "file" link-type))
         (path (if is-file path-val raw-path))
         (is-image (ews-gemini-image-link-p link)))
    (if is-image
        ;; For image attachments, emit standard Gemtext link line directly in content flow
        (let* ((input-file (or (plist-get info :input-file)
                               (org-element-property :path (plist-get info :parse-tree))
                               buffer-file-name
                               ""))
               (current-dir (file-name-directory (expand-file-name input-file)))
               (project-root (or (locate-dominating-file current-dir "content")
                                 default-directory))
               (base-dir (file-name-as-directory (expand-file-name "content" project-root)))
               (target-abs (if is-file (expand-file-name path-val current-dir) path))
               (resolved-path (if (and is-file (file-exists-p target-abs))
                                  (concat "/" (file-relative-name target-abs base-dir))
                                path))
               (parent (org-element-lineage link '(paragraph)))
               (caption (when parent (org-export-get-caption parent)))
               (label (cond
                       (desc (org-element-interpret-data desc))
                       (caption (org-export-data caption info))
                       (t (file-name-nondirectory path)))))
          (format "=> %s %s" (url-encode-url resolved-path) (org-trim (string-replace "\n" " " label))))
      ;; For text hyperlinks, output clean inline anchor text
      (let ((description (if (org-string-nw-p desc) desc (or raw-path ""))))
        (format "%s%s%s"
                (car org-gemini-link-symbol)
                description
                (cadr org-gemini-link-symbol))))))

(defun ews-gemini-paragraph (_paragraph contents _info)
  "Format paragraph CONTENTS for Gemtext export.

_PARAGRAPH is the paragraph AST element node (unused).
CONTENTS is the transcoded text of the paragraph.
_INFO is a plist containing export options and document state (unused).

Trims leading and trailing whitespace to eliminate upstream `ox-gemini'
trailing-space bugs and ensure Gemtext link lines (`=>') start flush-left
at column zero. Suppresses paragraphs that resolve to empty whitespace,
returning an empty string. Returns the flattened paragraph text followed
by double newlines for paragraph separation."
  (let ((trimmed (string-trim (or contents ""))))
    (if (string-empty-p trimmed)
        ""
      (if (string-prefix-p "=>" trimmed)
          (concat trimmed "\n\n")
        (concat (replace-regexp-in-string "\n" " " trimmed) "\n\n")))))

(advice-add 'org-gemini-paragraph :override #'ews-gemini-paragraph)

(defun ews-gemini-describe-links (links _width info)
  "Format a block of Gemtext LINK lines for non-image LINKS in the current section.
When a link has no description (bare link), omit the label per Gemtext specification."
  (let ((text-links (seq-remove #'ews-gemini-image-link-p links)))
    (if text-links
        (concat
         (mapconcat
          (lambda (link)
            (let* ((raw-path (org-element-property :raw-link link))
                   (link-type (org-element-property :type link))
                   (is-file (string= "file" link-type))
                   (path-val (org-element-property :path link))
                   (path (cond
                          ((and is-file (string-match "\\`\\(.*?\\)\\.org\\(::.*\\)?\\'" path-val))
                           (concat (match-string 1 path-val) ".gmi"))
                          (is-file path-val)
                          (t raw-path)))
                   (desc (org-element-contents link))
                   (anchor (when desc
                             (org-trim (string-replace "\n" " " (org-element-interpret-data desc))))))
              (if (org-string-nw-p anchor)
                  (format "=> %s %s" (url-encode-url path) anchor)
                (format "=> %s" (url-encode-url path)))))
          text-links
          "\n")
         "\n\n")
      "")))

(advice-add 'org-gemini--describe-links :override #'ews-gemini-describe-links)

;; Sitemap & Gemlog Feed
(defun ews-gemini-sitemap-format-entry (entry style project)
  "Format Gemini feed ENTRY as a reverse-chronological link line.
Excludes section index pages and error pages so the feed only contains posts."
  (unless (member (file-name-nondirectory entry)
                  '("index.org" "about.org" "404.org" "toc.org" "theindex.org" "gemlog.org" "sitemap.org"))
    (let* ((title (org-publish-find-title entry project))
           (date (org-publish-find-date entry project))
           (gmi-url (concat "/" (file-name-sans-extension entry) ".gmi"))
           (date-str (if date (format "%s " (format-time-string "%Y-%m-%d" date)) "")))
      (format "=> %s %s%s" gmi-url date-str (or title entry)))))

(defun ews-gemini-sitemap-builder (title list)
  "Build the flat chronological Gemini feed with TITLE from LIST."
  (let* ((raw-entries (mapcar #'car (cdr list)))
         (entries (delq nil (remove "" raw-entries))))
    (concat "#+title: " title "\n"
            "#+options: toc:nil meta:nil\n\n"
            "> Subscribe to this page in your Gemini client for recent updates.\n\n"
            "#+begin_export gemini\n"
            (string-join entries "\n")
            "\n#+end_export\n")))

(defun ews-org-export-gemini-footer-text ()
  "Generate Gemini footer colophon."
  (let* ((pub-year (string-trim (format-time-string "%Y")))
         (pub-date (string-trim (format-time-string "%e %B %Y")))
         (creator-string (format "Emacs %s (Org mode %s)" emacs-version (org-version))))
    (concat "## Colophon\n\n"
            (format "🄯 %s, Peter Prevos. Licensed under Creative Commons BY-SA 4.0 CC BY SA\n\n" pub-year)
            (format "This capsule was generated with %s on %s\n\n" creator-string pub-date)
            "=> /index.gmi ⌂ Home\n"
            "=> /about.gmi ∃ About the Horizon of Reason\n"
            "=> /gemlog.gmi ☰ Gemlog feed\n")))

(defun ews-gemini-final-output-filter (output backend info)
  "Apply single-line subtitle and append colophon to Gemini OUTPUT.

BACKEND is 'gemini and INFO is the list of project properties."
  (if (org-export-derived-backend-p backend 'gemini)
      (let* ((with-meta (ews-org-gemini-auto-subtitle output backend info))
             (colophon (ews-org-export-gemini-footer-text)))
        (if (string-match-p "## Colophon" with-meta)
            with-meta
          (concat (string-trim-right with-meta) "\n\n" colophon "\n")))
    output))

;; Set publishing parameters
(setq org-publish-project-alist
      `(("gmi-pages"
         :base-directory "content"
         :publishing-directory "gmi"
         :base-extension "org"
         :with-meta t
         :with-toc nil
         :with-emphasize t ;; Parse emphasis so transcoders strip the markers
         :publishing-function org-gemini-publish-to-gemini
         :recursive t
         :exclude ,(concat "^toc\\.org$\\|^sitemap\\.org$\\|" (ews-org-publish-exclude-regex "content"))
         :filter-final-output (ews-gemini-final-output-filter)
         :auto-sitemap t
         :sitemap-filename "gemlog.org"
         :sitemap-title "Gemlog feed"
         :sitemap-style list
         :sitemap-sort-files anti-chronologically
         :sitemap-format-entry ews-gemini-sitemap-format-entry
         :sitemap-function ews-gemini-sitemap-builder)

        ("gmi-images"
         :base-directory "content/images"
         :publishing-directory "gmi/images"
         :base-extension "png\\|jpg\\|webp\\|svg"
         :recursive t
         :publishing-function org-publish-attachment)

        ("gmi-static"
         :base-directory "static-gmi"
         :publishing-directory "gmi"
         :base-extension "txt"
         :publishing-function org-publish-attachment)

        ("gemini"
         :components ("gmi-pages" "gmi-images" "gmi-static"))))

;;; Publish function
(defun ews-publish ()
  "Publish the entire Gemini capsule."
  (org-publish "gemini" (bound-and-true-p ews-rw))
  (message "Capsule published"))

(provide 'publish-gmi)
;;; publish-gmi.el ends here
