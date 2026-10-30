;;; publish-www.el --- Publishing peterprevos.com -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Peter Prevos
;;
;; Author: Peter Prevos <peter@prevos.net>
;; URL: https://github.com/pprevos/peterprevos.com/
;;
;;; Commentary:
;; Using org-export to generate the peterprevos.com website and Gemini capsule.
;; HTML export configuration, Open Graph, and JSON-LD
;;
;;; Code:

;; Load shared publishing definitions and package environment
(add-to-list 'load-path (file-name-directory (expand-file-name (or load-file-name buffer-file-name "."))))
(require 'publish-common)

;; Load packages
(require 'ox-publish)
(require 'htmlize)
(require 'json)
(require 'url-util)

;; HTML FUNCTIONS

;; Use CSS classes instead of inline styles for syntax-highlighted code blocks
(setq org-html-htmlize-output-type 'css)

;; Define static HTML head, preamble and postamble
(defconst ews-org-html-head-static
  (ews-file-to-string "templates/head.html")
  "Static HTML head tags loaded from template.")

(defconst ews-org-html-preamble-static
  (ews-file-to-string "templates/preamble.html")
  "Static HTML navigation preamble loaded from template.")

(defcustom ews-org-html-default-social-card-image "images/social/default-social-card-image.png"
  "Default social card image path relative to site root or absolute URL.
Used for Open Graph and Twitter cards when no #+image: keyword is specified."
  :type 'string
  :group 'ews)

(defun ews-org-html-preamble (info)
  "Generate dynamic HTML preamble using INFO.
Appends a breadcrumb trail on article pages (article is non-nil)."
  (let* ((file (or (plist-get info :input-file)
                   (org-element-property :path (plist-get info :parse-tree))
                   buffer-file-name
                   default-directory))
         (category (ews-current-category file info))
         (article-p (plist-get info :article))
         (raw-title (plist-get info :title))
         (title (cond ((stringp raw-title) raw-title)
                      (raw-title (org-export-data raw-title info))
                      (t "")))
         (clean-title (substring-no-properties title))
         (breadcrumb
          (when (and article-p category)
            (format
             "<nav class=\"breadcrumb\" aria-label=\"Breadcrumb\"><a href=\"/\">Home</a> ❯ <a href=\"/%s/\">%s</a> ❯ <span>%s</span></nav>\n"
             category (capitalize category) clean-title))))
    (concat ews-org-html-preamble-static breadcrumb)))

(defconst ews-org-html-postamble-template
  (ews-file-to-string "templates/postamble.html")
  "Static HTML postamble template string.")

(defun ews-org-html-postamble (info)
  "Generate dynamic HTML postamble (footer) using template and INFO."
  (let* ((file (or (plist-get info :input-file)
                   (org-element-property :path (plist-get info :parse-tree))
                   buffer-file-name
                   default-directory))
         (category (ews-current-category file info))
         (feed-url (if category
                       (format "/%s/atom.xml" category)
                     "/toc/#feeds"))
         (feed-label (if category
                          (format "%s Atom feed" (capitalize category))
                        "Atom feeds"))
         (raw-title (plist-get info :title))
         (title (cond ((stringp raw-title) raw-title)
                      (raw-title (org-export-data raw-title info))
                      (t "")))
         (raw-author (plist-get info :author))
         (author (cond ((stringp raw-author) raw-author)
                        (raw-author (org-export-data raw-author info))
                        (t user-full-name)))
         (email user-mail-address)
         (creator (or (plist-get info :creator) "Emacs Org mode"))
         (date (format-time-string "%e %B %Y"))
         (base-url (or (plist-get info :base-url) "https://peterprevos.com/"))
         (domain (directory-file-name (replace-regexp-in-string "\\`https?://" "" base-url)))
         (filename (file-name-sans-extension (file-name-nondirectory file)))
         (gemini-url (if category
                         (format "gemini://%s/%s/%s.gmi" domain category filename)
                       (format "gemini://%s/%s.gmi" domain filename))))
    (format-spec
     ews-org-html-postamble-template
     `((?t . ,title)
       (?a . ,author)
       (?e . ,(format "<a href=\"mailto:%s?subject=%s\">%s</a>"
                      email
                      (url-hexify-string title)
                      author))
       (?c . ,creator)
       (?C . ,date)
       (?f . ,feed-url)
       (?F . ,feed-label)
       (?g . ,gemini-url)))))

(with-eval-after-load 'ox
  (add-to-list 'org-export-options-alist '(:image "IMAGE" nil nil t))
  (add-to-list 'org-export-options-alist '(:lastmod "LASTMOD" nil nil t)))

(defun ews-format-iso-date (raw-date)
  "Convert RAW-DATE timestamp or string into ISO-8601 YYYY-MM-DDTHH:MM:SS+00:00."
  (cond
   ((and (consp raw-date) (eq (org-element-type (car raw-date)) 'timestamp))
    (org-format-timestamp (car raw-date) "%Y-%m-%dT00:00:00+00:00"))
   ((and (stringp raw-date) (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" raw-date))
    (concat (match-string 1 raw-date) "T00:00:00+00:00"))
   (t nil)))

(defun ews-org-html-open-graph-tags (info)
  "Generate complete Open Graph, Twitter cards, and Schema.org structured data.
INFO is the plist holding export options and document state."
  (let* ((site-name (plist-get info :site-name))
	 (title (or (org-export-data (plist-get info :title) info) site-name))
	 (article-p (plist-get info :article))
	 (description (or (plist-get info :description) title))
         (author (or (org-export-data (plist-get info :author) info) user-full-name))
         (base-url (or (plist-get info :base-url) ews-canonical-base-url))
         ;; Canonical URL Resolution
         (input-file (or (plist-get info :input-file)
                         (org-element-property :path (plist-get info :parse-tree))
                         buffer-file-name
                         ""))
         (content-dir (ews-org-publish-base-dir info))
         (rel-file (when (org-string-nw-p input-file)
                     (file-relative-name (expand-file-name input-file) content-dir)))
         (url-slug (cond
                    ((null rel-file) "")
                    ((string-equal rel-file "index.org") "")
                    ((string-suffix-p "/index.org" rel-file)
                     (substring rel-file 0 (- (length rel-file) 9)))
                    ((string-equal rel-file "404.org") "404.html")
                    (t (concat (file-name-sans-extension rel-file) "/"))))
         (canonical-url (concat (file-name-as-directory base-url) url-slug))
         ;; Page Type: "article" vs "website"
         (og-type (if article-p "article" "website"))
         ;; Section & Tags
         (section-name (when (and article-p (file-name-directory rel-file))
                         (capitalize (directory-file-name (file-name-directory rel-file)))))
         (filetags (plist-get info :filetags))
         ;; Dates (ISO-8601)
         (pub-date (ews-format-iso-date (plist-get info :date)))
         (mod-date (or (ews-format-iso-date (plist-get info :lastmod))
                       (when (and input-file (file-exists-p input-file))
                         (format-time-string "%Y-%m-%dT%H:%M:%S+00:00"
                                             (file-attribute-modification-time (file-attributes input-file))))
                       pub-date))
         ;; Image URL resolution
         (default-image (or (plist-get info :default-social-card-image)
                            (bound-and-true-p ews-org-html-default-social-card-image)))
         (slug-name (file-name-base (or input-file "")))
         (slug-image (and (org-string-nw-p slug-name)
                          (let ((path (format "images/social/%s.png" slug-name)))
                            (when (file-exists-p (expand-file-name path content-dir))
                              path))))
         (raw-image
          (or (plist-get info :image)
              slug-image
              (when (and default-image
                         (or (string-prefix-p "http" default-image)
                             (let ((disk-path (expand-file-name
                                               (if (string-prefix-p "/" default-image)
                                                   (substring default-image 1)
                                                 default-image)
                                               content-dir)))
                               (file-exists-p disk-path))))
                default-image)))
         (image-url (when raw-image
                      (cond
                       ((string-prefix-p "http" raw-image) raw-image)
                       ((string-prefix-p "/" raw-image) (concat (directory-file-name base-url) raw-image))
                       (t (concat (file-name-as-directory base-url) raw-image)))))
         ;; JSON-LD Structured Data
         (schema-data
          (if article-p
              `((@context . "https://schema.org")
                (@type . "BlogPosting")
                (mainEntityOfPage . ((@type . "WebPage") (@id . ,canonical-url)))
                (headline . ,title)
                (description . ,description)
                (url . ,canonical-url)
                ,@(when image-url `((image . [,image-url])))
                ,@(when pub-date `((datePublished . ,pub-date)))
                ,@(when mod-date `((dateModified . ,mod-date)))
                (author . ((@type . "Person")
                           (name . ,author)
                           (url . ,(concat (file-name-as-directory base-url) "about/"))))
                (publisher . ((@type . "Person")
                              (name . ,author)
                              (url . ,base-url))))
            `((@context . "https://schema.org")
              (@type . "WebSite")
              (name . ,site-name)
              (url . ,base-url)
              (description . ,description)
              ,@(when image-url `((image . [,image-url])))
              (author . ((@type . "Person") (name . ,author))))))
         (breadcrumb-data
          (when (and article-p section-name)
            `((@context . "https://schema.org")
              (@type . "BreadcrumbList")
              (itemListElement .
               [((@type . "ListItem")
                 (position . 1)
                 (name . "Home")
                 (item . ,base-url))
                ((@type . "ListItem")
                 (position . 2)
                 (name . ,section-name)
                 (item . ,(concat (file-name-as-directory base-url) (downcase section-name) "/")))
                ((@type . "ListItem")
                 (position . 3)
                 (name . ,title)
                 (item . ,canonical-url))]))))
         (gemini-url
          (when (and (org-string-nw-p rel-file)
                     (not (string-equal rel-file "404.org")))
            (concat "gemini://peterprevos.com/" (file-name-sans-extension rel-file) ".gmi")))
         (category (when (file-name-directory rel-file)
                     (directory-file-name (file-name-directory rel-file)))))
    (concat
     ;; Canonical URL and Cross-Protocol Gemini Discovery
     (format "<link rel=\"canonical\" href=\"%s\">\n" canonical-url)
     (when gemini-url
       (format "<link rel=\"alternate\" type=\"text/gemini\" href=\"%s\" title=\"Gemini capsule\">\n" gemini-url))
     ;; Category Atom Feed
     (when category
       (format "<link rel=\"alternate\" type=\"application/atom+xml\" href=\"%s%s/atom.xml\" title=\"%s Atom Feed\">\n"
               (file-name-as-directory base-url) category (capitalize category)))
     ;; Open Graph Base
     "<!-- Open Graph -->\n"
     (format "<meta property=\"og:site_name\" content=\"%s\">\n" site-name)
     (format "<meta property=\"og:title\" content=\"%s\">\n" title)
     (format "<meta property=\"og:description\" content=\"%s\">\n" description)
     (format "<meta property=\"og:url\" content=\"%s\">\n" canonical-url)
     (format "<meta property=\"og:type\" content=\"%s\">\n" og-type)
     "<meta property=\"og:locale\" content=\"en_AU\">\n"
     ;; Article-specific metadata
     (when article-p
       (concat
        (when section-name (format "<meta property=\"article:section\" content=\"%s\">\n" section-name))
        (when pub-date (format "<meta property=\"article:published_time\" content=\"%s\">\n" pub-date))
        (when mod-date (format "<meta property=\"article:modified_time\" content=\"%s\">\n" mod-date))
        (format "<meta property=\"article:author\" content=\"%s\">\n" author)
        (when filetags
          (mapconcat (lambda (tag) (format "<meta property=\"article:tag\" content=\"%s\">\n" tag))
                     filetags ""))))
     ;; Image (Open Graph)
     (when image-url
       (concat
        (format "<meta property=\"og:image\" content=\"%s\">\n" image-url)
        "<meta property=\"og:image:width\" content=\"1200\">\n"
        "<meta property=\"og:image:height\" content=\"630\">\n"))
     ;; Twitter / X Cards
     "<!-- Twitter cards -->\n"
     (if image-url
         (concat
          "<meta name=\"twitter:card\" content=\"summary_large_image\">\n"
          (format "<meta name=\"twitter:title\" content=\"%s\">\n" title)
          (format "<meta name=\"twitter:description\" content=\"%s\">\n" description)
          (format "<meta name=\"twitter:image\" content=\"%s\">\n" image-url))
       (concat
        "<meta name=\"twitter:card\" content=\"summary\">\n"
        (format "<meta name=\"twitter:title\" content=\"%s\">\n" title)
        (format "<meta name=\"twitter:description\" content=\"%s\">\n" description)))
     ;; Schema.org JSON-LD Structured Data
     "<!-- Structured Data -->\n"
     "<script type=\"application/ld+json\">\n"
     (json-encode schema-data)
     "\n</script>\n"
     (when breadcrumb-data
       (concat "<script type=\"application/ld+json\">\n"
               (json-encode breadcrumb-data)
               "\n</script>\n")))))

(defun ews-org-html-clean-meta-filter (output backend _info)
  "Strip XHTML trailing slashes on <meta> tags in HTML OUTPUT.
BACKEND is the active export backend and _INFO is the unused export plist."
  (if (org-export-derived-backend-p backend 'html)
      (replace-regexp-in-string "<meta\\([^>]*?\\)[ \t]*/>" "<meta\\1>" output)
    output))

(defun ews-org-html-filter-figure-paragraph (text backend _info)
  "Unwrap standalone <figure> elements from invalid enclosing <p> tags in HTML.
TEXT is the transcoded paragraph.  BACKEND is the active export backend.
_INFO is the unused export plist."
  (if (org-export-derived-backend-p backend 'html)
      (replace-regexp-in-string
       "<p>[ \t\n]*\\(<figure[>[:space:]][[:ascii:][:nonascii:]]*?</figure>\\)[ \t\n]*</p>"
       "\\1"
       text)
    text))

;; Configure the sitemap
(defun ews-sitemap-format-entry (entry _style project)
  "Format sitemap ENTRY with publication date.
ENTRY is a file name.
_STYLE is the unused style of the sitemap.
PROJECT is the metadata of the current project."
  (if (directory-name-p entry)
      (capitalize (file-name-nondirectory (directory-file-name entry)))
    (let ((title (org-publish-find-title entry project))
          (date  (org-publish-find-date entry project)))
      (if date
          (format "%s: [[file:%s][%s]]"
                  (format-time-string "%Y-%m-%d" date)
                  entry
                  title)
        (format "[[file:%s][%s]]" entry title)))))

(defun ews-sitemap-builder-html (title list)
  "Build HTML sitemap keeping subdirectories and inserting atom-feeds macro.
Drops root files.  TITLE is the title of the site map.  LIST is an internal
representation of the files to include, as returned by `org-list-to-lisp'."
  (let ((filtered-list (cons 'unordered
                             (cl-remove-if-not
                              (lambda (item) (consp (cadr item)))
                              (cdr list)))))
    (concat "#+title: " title "\n"
            "#+options: toc:nil title:t article:nil gmi:nil\n\n"
            (org-list-to-org filtered-list)
	    "\n\n"
	    "* Atom Feeds\n"
            ":PROPERTIES:\n"
            ":CUSTOM_ID: feeds\n"
            ":END:\n"
            "Subscribe to category feeds using your RSS/Atom reader:\n\n"
            "{{{atom-feeds}}}\n\n")))

;; Set global publishing parameters to avoid repetition
(setq org-export-with-toc nil
      org-export-with-todo-keywords nil
      org-export-with-drawers nil
      org-export-with-section-numbers nil
      org-html-head-include-scripts nil
      org-html-head-include-default-style nil
      org-html-doctype "html5"
      org-html-html5-fancy t
      org-html-divs '((preamble "header" "preamble")
		      (content "main" "content")
		      (postamble "footer" "postamble"))
      org-html-container-element "section"
)

;; Set publishing parameters
(setq org-publish-project-alist
      `(("html"
         :base-directory "content"
         :recursive t
	 :exclude ,(string-join
                    (delq nil (list "^gemlog\\.org$"
                                   "^publishing-schedule\\.org$"
                                   (ews-org-publish-exclude-regex (ews-org-publish-base-dir) 'www)))
                   "\\|")
	 :publishing-directory "www"
	 :base-url ,ews-canonical-base-url
	 :site-name "The Horizon of Reason"
	 :default-social-card-image "images/social/default-social-card-image.png"
	 :publishing-function ews-org-publish-to-pretty-html
	 :preparation-function ews-org-publish-generate-llms-txt
	 :completion-function (ews-org-publish-generate-sitemap-xml
                               ews-org-publish-generate-publishing-schedule
                               ews-org-publish-generate-category-feeds)
	 :auto-sitemap t
	 :sitemap-filename "toc.org"
	 :sitemap-title "Table of Contents"
	 :sitemap-style tree
	 :sitemap-format-entry ews-sitemap-format-entry
	 :sitemap-function ews-sitemap-builder-html
	 :sitemap-sort-files anti-chronologically
	 :sitemap-sort-folders first
	 :html-head ,ews-org-html-head-static
	 :html-head-extra ews-org-html-open-graph-tags
	 :html-metadata-timestamp-format "%e %B %Y"
	 :html-preamble ews-org-html-preamble
	 :html-postamble ews-org-html-postamble
	 :filter-link (ews-org-html-pretty-link-filter)
	 :filter-parse-tree (ews-org-html-auto-subtitle)
	 :filter-paragraph (ews-org-html-filter-figure-paragraph)
	 :filter-final-output (ews-org-html-clean-meta-filter)
	 :makeindex t)
	("html-always"
	 ;; Ensure that pages with {{{list-files}}} are always published
         :base-directory "content"
	 :exclude ".*"
	 :include ,(ews-org-publish-dynamic-files)
	 :recursive t
         :publishing-directory "www"
	 :base-url ,ews-canonical-base-url
	 :publishing-function ews-org-publish-to-pretty-html
	 :html-head ,ews-org-html-head-static
	 :html-head-extra ews-org-html-open-graph-tags
	 :html-preamble ews-org-html-preamble
	 :html-postamble ews-org-html-postamble
	 :filter-link (ews-org-html-pretty-link-filter)
	 :filter-parse-tree (ews-org-html-auto-subtitle)
	 :filter-paragraph (ews-org-html-filter-figure-paragraph)
	 :filter-final-output (ews-org-html-clean-meta-filter))
        ("images"
         :base-directory "content/images"
         :publishing-directory "www/images"
         :base-extension "png\\|jpg\\|webp\\|svg"
         :recursive t
         :publishing-function org-publish-attachment)
        ("static"
         :base-directory "content/static-www"
         :publishing-directory "www"
         :base-extension any
         :recursive t
         :publishing-function org-publish-attachment)
	("website"
         :components ("html" "images" "static"))))

;;; Publish function
(defun ews-publish ()
  "Publish the World Wide Web version."
  (org-publish "website" (or (bound-and-true-p ews-rw)
                             (bound-and-true-p ews-drafts)))
  (org-publish "html-always" t)
  (message "Website published!"))

(provide 'publish-www)
;;; publish-www.el ends here
