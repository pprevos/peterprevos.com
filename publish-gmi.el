;;; publish-gmi.el --- Publishing peterprevos.com Gemini Capsule -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Peter Prevos
;;
;; Author: Peter Prevos <peter@prevos.net>
;; URL: https://github.com/pprevos/peterprevos.com/
;;
;;; Commentary:
;; Using org-export to generate the peterprevos.com website and Gemini capsule.
;; Gemini export configuration and Gemtext AST transcoders
;;
;;; Code:

;; Load shared publishing definitions and package environment
(add-to-list 'load-path (file-name-directory
			 (expand-file-name
			  (or load-file-name buffer-file-name "."))))
(require 'publish-common)

;; Updates to ox-gemini
(defun ews-gemini-export-snippet (snippet _contents _info)
  "Transcode an Org export SNIPPET into Gemtext, e.g. @@gmi:=> link@@.
Supports snippets targeted to gemini, gmi, or gemtext (case-insensitive)."
  (when (member (downcase (symbol-name (org-export-snippet-backend snippet)))
                '("gemini" "gmi" "gemtext"))
    (org-element-property :value snippet)))

(defun ews-gemini-example-block (example-block _contents info)
  "Transcode an EXAMPLE-BLOCK element into a Gemtext preformatted block."
  (let* ((caption (org-export-get-caption example-block))
         (name (or (and caption (org-export-data caption info))
                   (org-element-property :name example-block)
                   ""))
         (alt (if (org-string-nw-p name) (concat " " (string-trim name)) ""))
         (value (org-element-property :value example-block)))
    (format "```%s\n%s```\n\n"
            alt
            (if (string-suffix-p "\n" value) value (concat value "\n")))))

;; Strip emphasis markers (Gemtext has no inline bold/italics syntax)
;; and support Gemini export macros and preformatted example blocks
(let ((backend (org-export-get-backend 'gemini)))
  (setf (org-export-backend-transcoders backend)
        (append '((italic . (lambda (_i contents _info) contents))
                  (bold . (lambda (_b contents _info) contents))
                  (underline . (lambda (_u contents _info) contents))
                  (strike-through . (lambda (_s contents _info) contents))
                  (verbatim . (lambda (v _c _info)
                                (format "`%s`" (org-element-property :value v))))
                  (code . (lambda (c _c _info)
                            (format "`%s`" (string-trim (org-element-property :value c)))))
                  (example-block . ews-gemini-example-block)
                  (export-snippet . ews-gemini-export-snippet))
                (org-export-backend-transcoders backend))))

;; Override existing function to ensure only the title is a level one heading.
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

;; Customise how ox-gemini marks inline links.
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
  "Transcode an Org LINK element into Gemtext. Returns a Gemtext-formatted string.

LINK is the link AST node representing the Org hyperlink or image.
DESC is the transcoded description string if the link has explicit anchor
text (e.g. \"[[path][desc]]\"), or nil for bare links (e.g. \"[[path]]\").
INFO is a plist containing export options and document state.

This function overrides upstream `ox-gemini-link' with dual behavior:

1. Standalone Images / Media:
   If LINK points to an image file it creates a canonical Gemtext link line:
   (`=> URL LABEL`) directly into the document flow where the figure occurs.
   The LABEL is resolved in order of precedence:
     a. Explicit link description (DESC).
     b. Enclosing paragraph `#+caption:' keyword.
     c. File base name fallback.
   URLs are sanitized via `url-encode-url' so spaces do not truncate the link.

2. Inline Hyperlinks:
   For non-image links, Gemtext cannot embed hyperlinks inside running prose.
   Instead of forcing bracket delimiters (`[text]`), this function emits DESC
   wrapped with `org-gemini-link-symbol' (by default `(\"[\" \"]\")' for clean,
   prose). The destination URL is collected and output at the end of the section
   by `ews-gemini-describe-links'."
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
               (base-dir (ews-org-publish-base-dir info))
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
at column zero.  Suppresses paragraphs that resolve to empty whitespace,
returning an empty string.  Returns the flattened paragraph text followed
by double newlines for paragraph separation."
  (let ((trimmed (string-trim (or contents ""))))
    (if (string-empty-p trimmed)
        ""
      (if (string-prefix-p "=>" trimmed)
          (concat trimmed "\n\n")
        (concat (replace-regexp-in-string "\n" " " trimmed) "\n\n")))))

(advice-add 'org-gemini-paragraph :override #'ews-gemini-paragraph)

(defun ews-gemini-describe-links (links _width _info)
  "Format a block of Gemtext link lines for non-image LINKS.
_WIDTH is the unused line width and _INFO is the unused export plist."
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
(defun ews-gemini-sitemap-format-entry (entry _style project)
  "Format Gemini feed ENTRY as a reverse-chronological link line.
_STYLE is the unused sitemap style. PROJECT is the publishing project.
Excludes section index pages and error pages."
  (unless (member (file-name-nondirectory entry)
		  ;; TODO: List all org file in :base-directory with function
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
            "#+options: toc:nil article:nil\n\n"
            "> Subscribe to this page in your Gemini client for updates.\n\n"
	    "## My posts\n\n"
            "#+begin_export gemini\n"
            (string-join entries "\n")
            "\n#+end_export\n")))

(defun ews-org-export-gemini-footer-text ()
  "Generate Gemini footer colophon."
  (let* ((pub-year (string-trim (format-time-string "%Y")))
         (pub-date (string-trim (format-time-string "%e %B %Y")))
         (creator-string (format "Emacs %s (Org mode %s)" emacs-version (org-version))))
    (concat "## Colophon\n\n"
            "=> /index.gmi ⌂ Home\n"
            "=> /about.gmi ∃ About the Horizon of Reason\n"
            "=> /gemlog.gmi ☰ Gemlog feed\n"
	    "=> https://peterprevos.com Website version\n"
	    (format "=> https://creativecommons.org/licenses/by-sa/4.0/ 🄯 %s, %s. Creative Commons BY-SA 4.0 CC BY SA\n"
		    pub-year user-full-name)
	    (format "=> https://github.com/pprevos/peterprevos.com/ Generated with %s on %s\n"
		    creator-string pub-date))))

(defun ews-gemini-final-output-filter (output backend info)
  "Apply single-line subtitle and append colophon to Gemini OUTPUT.

BACKEND is \\='gemini and INFO is the list of project properties."
  (if (org-export-derived-backend-p backend 'gemini)
      (let* ((body-text (ews-org-gemini-auto-subtitle output backend info))
             (colophon (ews-org-export-gemini-footer-text)))
        (if (string-match-p "## Colophon" body-text)
            body-text
          (concat (string-trim-right body-text) "\n\n" colophon "\n")))
    output))

;; Set publishing parameters
(setq org-publish-project-alist
      `(("gmi-pages"
         :base-directory "content"
         :publishing-directory "gmi"
         :base-extension "org"
         :article t
         :with-toc nil
         :with-emphasize t
	 :with-drawers nil
         :publishing-function org-gemini-publish-to-gemini
         :recursive t
         :exclude ,(string-join
                    (delq nil (list "^toc\\.org$"
                                    "^sitemap\\.org$"
                                    (ews-org-publish-exclude-regex (ews-org-publish-base-dir) 'gmi)))
                    "\\|")
         :filter-final-output (ews-gemini-final-output-filter)
         :auto-sitemap t
         :sitemap-filename "gemlog.org"
         :sitemap-title "Horizon of Reason Gemlog Feed"
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
         :base-directory "content/static-gmi"
         :publishing-directory "gmi"
         :base-extension "txt"
         :publishing-function org-publish-attachment)

        ("gemini"
         :components ("gmi-pages" "gmi-images" "gmi-static"))))

;;; Publish function
(defun ews-publish ()
  "Publish the entire Gemini capsule."
  (org-publish "gemini" (or (bound-and-true-p ews-rw)
                            (bound-and-true-p ews-drafts)))
  (message "Capsule published"))

(provide 'publish-gmi)
;;; publish-gmi.el ends here
