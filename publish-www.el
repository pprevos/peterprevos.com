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

;; HTML FUNCTIONS

;; Define static HTML head, preamble and postamble
(defun ews-file-to-string (file)
  "Read a FILE and store it in a string."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name file))
    (buffer-string)))

(setq ews-org-html-head-static
      (ews-file-to-string "templates/head.html"))

(setq ews-org-html-preamble-static
      (ews-file-to-string "templates/preamble.html"))

(setq ews-org-html-postamble
      (ews-file-to-string "templates/postamble.html"))

(with-eval-after-load 'ox
  (add-to-list 'org-export-options-alist '(:image "IMAGE" nil nil t))
  (add-to-list 'org-export-options-alist '(:lastmod "LASTMOD" nil nil t)))

(defun ews-format-iso-date (raw-date)
  "Convert RAW-DATE timestamp or string into ISO-8601 YYYY-MM-DDTHH:MM:SS+00:00."
  (cond
   ((and (consp raw-date) (eq (org-element-type (car raw-date)) 'timestamp))
    (org-timestamp-format (car raw-date) "%Y-%m-%dT00:00:00+00:00"))
   ((and (stringp raw-date) (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" raw-date))
    (concat (match-string 1 raw-date) "T00:00:00+00:00"))
   (t nil)))

(defun ews-org-html-open-graph-tags (info)
  "Generate complete Open Graph, Twitter cards, and Schema.org JSON-LD structured data."
  (let* ((title (or (org-export-data (plist-get info :title) info) "The Horizon of Reason"))
         (description (or (plist-get info :description)
                          "The Horizon of Reason explores the limits of rationality through philosophical essays, digital asceticism, and creative worldbuilding."))
         (author (or (org-export-data (plist-get info :author) info) "Peter Prevos"))
         (base-url (or (plist-get info :base-url) "https://peterprevos.com/"))
         (site-name "The Horizon of Reason")
         ;; Canonical URL Resolution
         (input-file (or (plist-get info :input-file)
                         (org-element-property :path (plist-get info :parse-tree))
                         buffer-file-name
                         ""))
         (file-dir (file-name-directory (expand-file-name input-file)))
         (project-root (or (locate-dominating-file file-dir "content")
                           (expand-file-name ".")))
         (content-dir (file-name-as-directory
                       (expand-file-name (or (plist-get info :base-directory) "content") project-root)))
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
         (is-article (not (or (string-equal rel-file "index.org")
                              (string-suffix-p "/index.org" rel-file)
                              (string-equal rel-file "toc.org")
                              (string-equal rel-file "theindex.org")
                              (string-equal rel-file "404.org"))))
         (og-type (if is-article "article" "website"))
         ;; Section & Tags
         (section-name (when (and is-article (file-name-directory rel-file))
                         (capitalize (directory-file-name (file-name-directory rel-file)))))
         (filetags (plist-get info :filetags))
         ;; Dates (ISO-8601)
         (pub-date (ews-format-iso-date (plist-get info :date)))
         (mod-date (or (ews-format-iso-date (plist-get info :lastmod)) pub-date))
         ;; Image URL resolution
         (raw-image (plist-get info :image))
         (image-url (cond
                     ((null raw-image) (concat (file-name-as-directory base-url) "images/thirteen.jpg"))
                     ((string-prefix-p "http" raw-image) raw-image)
                     ((string-prefix-p "/" raw-image) (concat (directory-file-name base-url) raw-image))
                     (t (concat (file-name-as-directory base-url) raw-image))))
         ;; JSON-LD Structured Data
         (schema-data
          (if is-article
              `((@context . "https://schema.org")
                (@type . "BlogPosting")
                (mainEntityOfPage . ((@type . "WebPage") (@id . ,canonical-url)))
                (headline . ,title)
                (description . ,description)
                (url . ,canonical-url)
                (image . [,image-url])
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
              (author . ((@type . "Person") (name . ,author))))))
         (breadcrumb-data
          (when (and is-article section-name)
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
            (concat "gemini://peterprevos.com/" (file-name-sans-extension rel-file) ".gmi"))))
    (concat
     ;; Canonical URL
     (format "<link rel=\"canonical\" href=\"%s\" />\n" canonical-url)
     ;; Cross-Protocol Gemini Discovery
     (when gemini-url
       (format "<link rel=\"alternate\" type=\"text/gemini\" href=\"%s\" title=\"Gemini capsule\" />\n" gemini-url))
     ;; Open Graph Base
     (format "<meta property=\"og:site_name\" content=\"%s\" />\n" site-name)
     (format "<meta property=\"og:title\" content=\"%s\" />\n" title)
     (format "<meta property=\"og:description\" content=\"%s\" />\n" description)
     (format "<meta property=\"og:url\" content=\"%s\" />\n" canonical-url)
     (format "<meta property=\"og:type\" content=\"%s\" />\n" og-type)
     "<meta property=\"og:locale\" content=\"en_AU\" />\n"
     ;; Article-specific metadata
     (when is-article
       (concat
        (when section-name (format "<meta property=\"article:section\" content=\"%s\" />\n" section-name))
        (when pub-date (format "<meta property=\"article:published_time\" content=\"%s\" />\n" pub-date))
        (when mod-date (format "<meta property=\"article:modified_time\" content=\"%s\" />\n" mod-date))
        (format "<meta property=\"article:author\" content=\"%s\" />\n" author)
        (when filetags
          (mapconcat (lambda (tag) (format "<meta property=\"article:tag\" content=\"%s\" />\n" tag))
                     filetags ""))))
     ;; Image
     (format "<meta property=\"og:image\" content=\"%s\" />\n" image-url)
     "<meta property=\"og:image:width\" content=\"1200\" />\n"
     "<meta property=\"og:image:height\" content=\"630\" />\n"
     ;; Twitter / X Cards
     "<meta name=\"twitter:card\" content=\"summary_large_image\" />\n"
     (format "<meta name=\"twitter:title\" content=\"%s\" />\n" title)
     (format "<meta name=\"twitter:description\" content=\"%s\" />\n" description)
     (format "<meta name=\"twitter:image\" content=\"%s\" />\n" image-url)
     ;; Schema.org JSON-LD Structured Data
     "<script type=\"application/ld+json\">\n"
     (json-encode schema-data)
     "\n</script>\n"
     (when breadcrumb-data
       (concat "<script type=\"application/ld+json\">\n"
               (json-encode breadcrumb-data)
               "\n</script>\n")))))

;; Configure the sitemap
(defun ews-sitemap-format-entry (entry style project)
  "Format sitemap ENTRY with publication date.
ENTRY is a file name.  STYLE is the style of the sitemap.
PROJECT is the current project."
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
  "Build HTML sitemap keeping only subdirectories and dropping root files."
  (let* ((filtered-list (cons 'unordered
                              (cl-remove-if-not
                               (lambda (item) (consp (cadr item)))
                               (cdr list)))))
    (concat "#+title: " title "\n"
            "#+options: toc:nil title:t meta:nil\n\n"
            (org-list-to-org filtered-list))))

;; Set publishing parameters
(setq org-publish-project-alist
      `(("html"
         :base-directory "content"
         :recursive t
	 :exclude ,(concat "^gemlog\\.org$\\|^publishing-schedule\\.org$\\|" (ews-org-publish-exclude-regex "content"))
	 :publishing-directory "www"
	 :base-url "https://peterprevos.com/"
	 :publishing-function ews-org-publish-to-pretty-html
	 :preparation-function ews-org-publish-generate-llms-txt
	 :completion-function (ews-org-publish-generate-sitemap-xml
                               ews-org-publish-generate-publishing-schedule)
	 :auto-sitemap t
	 :sitemap-filename "toc.org"
	 :sitemap-title "Table of Contents"
	 :sitemap-style tree
	 :sitemap-format-entry ews-sitemap-format-entry
	 :sitemap-function ews-sitemap-builder-html
	 :sitemap-sort-files alphabetically
	 :sitemap-sort-folders first
	 :sitemap-ignore-case nil
	 :with-toc nil
	 :with-meta t
	 :with-todo-keywords nil
	 :section-numbers nil
	 :html-head-include-scripts nil
	 :html-head-include-default-style nil
	 :html-head ,ews-org-html-head-static
	 :html-head-extra ews-org-html-open-graph-tags
	 :html-doctype "html5"
	 :html-html5-fancy t
	 :html-divs ((preamble  "header" "preamble")
                     (content   "main"   "content")
                     (postamble "footer" "postamble"))
	 :html-container "section"
	 :html-metadata-timestamp-format "%e %B %Y"
	 :html-preamble ,ews-org-html-preamble-static
	 :html-postamble ,ews-org-html-postamble
	 :filter-link (ews-org-html-pretty-link-filter)
	 :filter-parse-tree (ews-org-html-auto-subtitle)
	 :makeindex t)
        ("images"
         :base-directory "content/images"
         :publishing-directory "www/images"
         :base-extension "png\\|jpg\\|webp\\|svg"
         :recursive t
         :publishing-function org-publish-attachment)
        ("static"
         :base-directory "static-www"
         :publishing-directory "www"
         :base-extension any
         :recursive t
         :publishing-function org-publish-attachment)
	("website"
         :components ("html" "images" "static"))))

;;; Publish function
(defun ews-publish ()
  "Publish the entire site."
  (org-publish "website" (bound-and-true-p ews-rw))
  (message "Website published!"))

(provide 'publish-www)
;;; publish-www.el ends here
