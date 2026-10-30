;;; publish-common.el --- Shared functions and macros for publishing -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 Peter Prevos
;;
;; Author: Peter Prevos <peter@prevos.net>
;; URL: https://github.com/pprevos/peterprevos.com/
;;
;;; Commentary:
;; Using org-export to generate the peterprevos.com website and Gemini capsule.
;; Shared functions, macros, filters, metadata extractors, and sitemaps
;;
;;; Code:

;; Initialize package sources
(require 'package)
(setq package-user-dir (expand-file-name ".packages"))
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(unless package-archive-contents
  (ignore-errors (package-refresh-contents)))

;; Styling for source blocks
(use-package htmlize
  :ensure t)

;; Export gemtext formatted documents from org-mode
(use-package ox-gemini
  :ensure t)

;; Generate Atom/RSS feeds
(use-package webfeeder
  :ensure t)

;; Activate built-in packages
(require 'org)
(require 'ox)
(require 'seq)
(require 'ox-publish)
(require 'image)

;; Generic variables
(setq user-full-name "Peter Prevos"
      user-mail-address "peter@prevos.net"
      org-publish-timestamp-directory ".org-timestamps/"
      org-export-with-broken-links t)

;; Set bibliography
(setq org-cite-global-bibliography
      (directory-files "~/documents/library/" t "^[A-Z|a-z|0-9].+.bib$"))

;; Register global macro and bespoke options
(with-eval-after-load 'ox
  (setq org-export-global-macros
               '(("list-files" . "(eval (ews-org-publish-list-files $1))")
		 ("atom-feeds" . "(eval (ews-org-publish-atom-feeds))")
		 ("youtube" . "@@html:<figure><iframe width=\"560\" height=\"315\" src=\"https://www.youtube.com/embed/$1\" title=\"$2\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share\" referrerpolicy=\"strict-origin-when-cross-origin\" allowfullscreen></iframe><figcaption>$2</figcaption></figure>@@@@latex:\\href{https://www.youtube.com/watch?v=$1}{Watch: $2 on YouTube}@@@@gemini:=> https://www.youtube.com/watch?v=$1 Watch: $2 on YouTube@@")
		 ("youtube-playlist" . "@@html:<figure><iframe width=\"560\" height=\"315\" src=\"https://www.youtube.com/embed/videoseries?list=$1\" title=\"$2\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share\" referrerpolicy=\"strict-origin-when-cross-origin\" allowfullscreen></iframe><figcaption>$2</figcaption></figure>@@@@latex:\\href{https://www.youtube.com/playlist?list=$1}{Watch: $2 on YouTube}@@@@gemini:=> https://www.youtube.com/playlist?list=$1 Watch: $2 on YouTube@@")
		 ("backend" . "@@html:website @@@@gemini:Gemini capsule @@@@latex:document@@")))
  (add-to-list 'org-export-options-alist
               '(:article nil "article" t))
  (add-to-list 'org-export-options-alist
               '(:www nil "www" t))
  (add-to-list 'org-export-options-alist
               '(:gmi nil "gmi" t)))

;; Project variables
(defvar ews-drafts nil
  "When non-nil, include drafts and future posts in published output.")

(defvar ews-rw nil
  "When non-nil, force full rebuild of all files.")

(defvar ews-canonical-base-url "https://peterprevos.com/"
  "Canonical production base URL for peterprevos.com.")

(defun ews-org-publish-base-dir (&optional info)
  "Resolve the absolute base content directory from INFO or `org-publish-project-alist'."
  (let* ((proj (or (assoc "html" org-publish-project-alist)
                   (assoc "gmi-pages" org-publish-project-alist)
                   (car org-publish-project-alist)))
         (base (or (when (and info (listp info)) (plist-get info :base-directory))
                   (when (and proj (listp (cdr proj))) (plist-get (cdr proj) :base-directory))
                   "content"))
         (root (or (locate-dominating-file default-directory base)
                   default-directory)))
    (file-name-as-directory (expand-file-name base root))))

;; Project-specific functions
(defun ews-file-to-string (file)
  "Read a FILE and store it in a string."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name file))
    (buffer-string)))

(defun ews-org-publish-category-dirs (&optional base-dir)
  "Return a list of category subdirectory names under BASE-DIR.
When BASE-DIR is nil, resolves from `ews-org-publish-base-dir'."
  (let* ((target-dir (or base-dir (ews-org-publish-base-dir)))
         (entries (when (file-directory-p target-dir)
                    (directory-files target-dir nil "^[^.]"))))
    (seq-filter
     (lambda (dir)
       (let ((full (expand-file-name dir target-dir)))
         (and (file-directory-p full)
              (not (member dir '("images" "static" "static-www" "static-gmi")))
              (directory-files full nil "\\.org$"))))
     entries)))

(defun ews-org-collect-file-keywords (file keywords)
  "Collect KEYWORDS from Org FILE in a temporary buffer.
Return an alist of (KEYWORD . VALUES)."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (org-collect-keywords keywords)))

(defun ews-org-draft-p (draft-value)
  "Return t if DRAFT-VALUE represents a non-nil draft status in #+draft:."
  (and draft-value
       (let ((value (downcase (string-trim draft-value))))
         (and (not (string-empty-p value))
              (not (member value '("nil" "no" "false" "0")))))))

(defun ews-org-future-p (date-val)
  "Return t if DATE-VAL represents a date in the future."
  (when (and date-val (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" date-val))
    (let ((date-str (match-string 1 date-val))
          (today-str (format-time-string "%Y-%m-%d")))
      (string> date-str today-str))))

(defun ews-org-file-excluded-p (file &optional backend ignore-drafts)
  "Return t if FILE is excluded from publication.
BACKEND can be \\='www or \\='gmi.
When IGNORE-DRAFTS is non-nil (or if `ews-drafts' is set), drafts and
future-dated files are included."
  (let* ((parsed (ews-org-collect-file-keywords file '("DATE" "DRAFT" "OPTIONS")))
         (draft (car (cdr (assoc "DRAFT" parsed))))
         (date (car (cdr (assoc "DATE" parsed))))
         (options (string-join (cdr (assoc "OPTIONS" parsed)) " "))
         (embargoed (or (ews-org-draft-p draft) (ews-org-future-p date))))
    (or (and embargoed
             (not (or ignore-drafts (bound-and-true-p ews-drafts))))
        (when backend
          (cond
           ((memq backend '(www html))
            (not (ews-org-option-value "www" options t)))
           ((memq backend '(gmi gemini gemtext))
            (not (ews-org-option-value "gmi" options t))))))))

(defun ews-org-publish-exclude-regex (&optional base-dir backend)
  "Return a regexp matching files in BASE-DIR excluded for the export BACKEND."
  (let* ((dir (expand-file-name (or base-dir (ews-org-publish-base-dir))))
         (all-files (when (file-directory-p dir)
                      (directory-files-recursively dir "\\.org$")))
         (excluded-rel-files
          (seq-filter
           (lambda (rel)
             (let ((full (expand-file-name rel dir)))
	       (ews-org-file-excluded-p full backend (bound-and-true-p ews-drafts))))
           (mapcar (lambda (f) (file-relative-name f dir)) all-files))))
    (when excluded-rel-files
      (mapconcat (lambda (f) (concat "^" (regexp-quote f) "$"))
                 excluded-rel-files
                 "\\|"))))

(defun ews-org-publish-get-directory-articles (&optional sort-by-order)
  "Collect metadata for non-embargoed articles in the current directory.
Used in the {{{list-files}}} export macro.
When `ews-drafts' is non-nil, then include all available articles.
When SORT-BY-ORDER is non-nil, order articles ascending by their #+order:
string.  Otherwise, sort reversed-alphabetically by date."
  (let* ((current-file (when buffer-file-name
                         (file-name-nondirectory buffer-file-name)))
         (files (seq-remove (lambda (f) (string-equal f current-file))
                            (directory-files default-directory nil "\\.org$")))
         articles)
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (org-mode)
        (let* ((parsed (org-collect-keywords
			'("TITLE" "DATE" "DESCRIPTION" "DRAFT" "ORDER" "OPTIONS")))
               (draft (car (cdr (assoc "DRAFT" parsed))))
               (timestamp (car (cdr (assoc "DATE" parsed))))
               (opts (string-join (cdr (assoc "OPTIONS" parsed)) " "))
               (target-excluded
                (cond
                 ((memq org-export-current-backend '(html))
                  (not (ews-org-option-value "www" opts t)))
                 ((memq org-export-current-backend '(gemini))
                  (not (ews-org-option-value "gmi" opts t))))))
          (unless (or target-excluded
                      (and (not (bound-and-true-p ews-drafts))
                           (or (ews-org-draft-p draft)
                               (ews-org-future-p timestamp))))
            (let* ((title (or (car (cdr (assoc "TITLE" parsed)))
                              (file-name-nondirectory file)))
                   (date (if (and timestamp (>= (length timestamp) 11))
                             (substring timestamp 1 11)
                           ""))
                   (desc (car (cdr (assoc "DESCRIPTION" parsed))))
                   (order (car (cdr (assoc "ORDER" parsed)))))
              (push (list :file file
                          :title title
                          :date date
                          :description desc
                          :order order)
                    articles))))))
    (sort articles
          (if sort-by-order
              (lambda (a b)
                (let ((oa (plist-get a :order))
                      (ob (plist-get b :order)))
                  (cond
                   ((and oa ob) (string< oa ob))
                   (oa t)
                   (ob nil)
                   (t (string> (or (plist-get a :date) "")
                               (or (plist-get b :date) ""))))))
            (lambda (a b)
              (string> (or (plist-get a :date) "")
                       (or (plist-get b :date) "")))))))

(defun ews-org-option-value (opt-name options-str default-val)
  "Extract boolean option OPT-NAME from OPTIONS-STR.
Return DEFAULT-VAL if not specified in OPTIONS-STR.
Lightweight regex lookup without the overhead of full-buffer parsing via
`org-export-get-environment' or the internal `org-export--parse-option-keyword' API."
  (if (and options-str (string-match (format "\\b%s:\\(t\\|nil\\)\\b" (regexp-quote opt-name)) options-str))
      (string-equal (match-string 1 options-str) "t")
    default-val))

(defun ews-current-category (file info)
  "Return the category subdirectory name for FILE using INFO, or nil if at root.
FILE is the source file path and INFO is the export communication plist."
  (let* ((base-dir (ews-org-publish-base-dir info))
         (rel (file-relative-name file base-dir)))
    (when (and (not (string-prefix-p ".." rel))
               (file-name-directory rel))
      (car (split-string rel "/")))))

(defun ews-org-publish-list-files-html (articles &optional sort-by-order)
  "Format ARTICLES as an Org list items for HTML export.
When SORT-BY-ORDER is non-nil, prepend the order keyword instead of the date."
  (if (null articles)
      "No content available yet"
    (mapconcat
     (lambda (art)
       (let* ((file (plist-get art :file))
              (title (plist-get art :title))
              (prefix-val (if sort-by-order
                              (or (plist-get art :order) (plist-get art :date))
                            (plist-get art :date)))
              (prefix-str (if (org-string-nw-p prefix-val) (format "%s: " prefix-val) ""))
              (desc (plist-get art :description))
              (desc-str (if (org-string-nw-p desc) (format ": %s" desc) "")))
         (format "- %s[[file:%s][%s]]%s" prefix-str file title desc-str)))
     articles
     "\n")))

(defun ews-org-publish-list-files-gemini (articles &optional sort-by-order)
  "Format list of ARTICLES as Gemtext link lines for Gemini export.
Exported as gemini block because ox-gemini otherwise duplicates content.
When SORT-BY-ORDER is non-nil, prepend the order keyword instead of the date."
  (if (null articles)
      "No content available yet"
    (concat
     "#+begin_export gemini\n"
     (mapconcat
      (lambda (art)
        (let* ((file (plist-get art :file))
               (gmi-file (concat (file-name-sans-extension file) ".gmi"))
               (title (plist-get art :title))
               (prefix-val (if sort-by-order
                               (or (plist-get art :order) (plist-get art :date))
                             (plist-get art :date)))
               (prefix-str (if (org-string-nw-p prefix-val) (format "%s " prefix-val) ""))
               (desc (plist-get art :description))
               (desc-str (if (org-string-nw-p desc) (format ": %s" desc) "")))
          (format "=> %s %s%s%s" gmi-file prefix-str title desc-str)))
      articles
      "\n")
     "\n#+end_export")))

(defun ews-org-publish-list-files (&optional sort-by-order)
  "Create a sorted list of links to articles based on current export backend.
When SORT-BY-ORDER is non-nil, sort using #+order: string and prepend order."
  (let ((articles (ews-org-publish-get-directory-articles sort-by-order)))
    (pcase org-export-current-backend
      ('gemini (ews-org-publish-list-files-gemini articles sort-by-order))
      ('html   (ews-org-publish-list-files-html articles sort-by-order))
      (_       (ews-org-publish-list-files-html articles sort-by-order)))))

(defun ews-org-publish-atom-feeds ()
  "Create an Org list of links to category Atom feeds for the HTML backend.
Uses `ews-org-publish-category-dirs' to discover categories."
  (let* ((project-root (or (locate-dominating-file default-directory "content")
                           default-directory))
         (base-dir (expand-file-name "content" project-root))
         (categories (ews-org-publish-category-dirs base-dir)))
    (mapconcat
     (lambda (cat)
       (let* ((cat-index (expand-file-name "index.org" (expand-file-name cat base-dir)))
              (meta (when (file-exists-p cat-index)
                      (ews-org-collect-file-keywords cat-index '("TITLE"))))
              (cat-title (or (car (cdr (assoc "TITLE" meta)))
                             (format "%s Articles" (capitalize cat)))))
         (format "- @@html:<a href=\"/%s/atom.xml\">%s Atom Feed</a>: %s@@"
                 cat (capitalize cat) cat-title)))
     categories
     "\n")))

(defun ews-org-publish-dynamic-files (&optional base-dir backend)
  "Return relative paths of all Org files in BASE-DIR containing dynamic macros.
Scans for macro calls like {{{list-files}}} and respects embargo/exclusions for BACKEND."
  (let* ((dir (or base-dir (ews-org-publish-base-dir)))
         (all-files (when (file-directory-p dir)
                      (directory-files-recursively dir "\\.org$")))
         matches)
    (dolist (file all-files)
      (unless (ews-org-file-excluded-p file (or backend 'www) (bound-and-true-p ews-drafts))
        (with-temp-buffer
          (insert-file-contents file)
          (when (re-search-forward "{{{list-files" nil t)
            (push (file-relative-name file dir) matches)))))
    (nreverse matches)))

(defun ews-org-get-page-meta (info)
  "Extract author, formatted date, word count, and reading time for INFO.
Used in subtitle when `article' is non-nil."
  (let* ((author (or (org-export-data (plist-get info :author) info) user-full-name))
         (raw-date (plist-get info :date))
         (date (if (and raw-date (consp raw-date) (eq (org-element-type (car raw-date)) 'timestamp))
                   (string-trim (org-format-timestamp (car raw-date) "%e %B %Y"))
                 (if raw-date (org-export-data raw-date info) "")))
         (words (count-words (point-min) (point-max)))
         (reading-time (max 1 (ceiling (/ (float words) 200)))))
    (list :author author :date date
	  :words (* (round (/ (float words) 10)) 10) :reading-time reading-time)))

(defun ews-org-html-auto-subtitle (tree backend info)
  "Construct a two-line HTML subtitle for articles when #+SUBTITLE: is nil.
- TREE is the Abstract Syntax Tree.
- BACKEND is the export backend (must be HTML)
- INFO is the plist holding export options and document state."
  (when (and (org-export-derived-backend-p backend 'html)
             (not (plist-get info :subtitle))
             (plist-get info :article))
    (let* ((meta (ews-org-get-page-meta info))
           (author (plist-get meta :author))
           (date (plist-get meta :date))
           (words (plist-get meta :words))
           (reading-time (plist-get meta :reading-time))
           (sub-text
            (format
             "@@html:<span class=\"subtitle-row\"><span>@@%s@@html:</span><span>@@%d words@@html:</span></span><span class=\"subtitle-row\"><span>@@%s@@html:</span><span>@@%d min read@@html:</span></span>@@"
             author words date reading-time))
           (parsed-sub (org-element-parse-secondary-string
                        sub-text (org-element-restriction 'keyword))))
      (plist-put info :subtitle parsed-sub)))
  tree)

(defun ews-org-gemini-auto-subtitle (output backend info)
  "Inject single-line metadata below article titles in Gemini OUTPUT.
The BACKEND must be \\='gemini and INFO is the plist holding options."
  (if (and (org-export-derived-backend-p backend 'gemini)
           (not (plist-get info :subtitle))
           (plist-get info :article))
      (let* ((meta (ews-org-get-page-meta info))
             (author (plist-get meta :author))
             (date (plist-get meta :date))
             (words (plist-get meta :words))
             (reading-time (plist-get meta :reading-time))
             (parts (delq nil
                          (list (concat "✎ " author)
                                (when (org-string-nw-p date) (concat " 📅 " date))
                                (format " ⏰ %d words (%d min read)" words reading-time))))
             (meta-line (concat (string-join parts) "\n\n")))
        (if (string-match "^# \\(.*?\\)\n\n" output)
            (replace-match (concat (match-string 0 output) meta-line) t t output)
          (concat meta-line output)))
    output))

(defun ews-org-publish-to-pretty-html (plist filename pub-dir)
  "Convert non-index HTML to subfolder for FILENAME using PLIST.
FILENAME is the source Org file and PUB-DIR is the publishing directory.
Outputs the export path as a string, e.g. category/article.org is exported as
category/article/index.html, except when already an index or 404 page."
  (let* ((file-base (file-name-base filename))
         (out-file (org-publish-org-to 'html filename ".html" plist pub-dir)))
    (if (member file-base '("index" "404"))
        out-file
      (let* ((target-dir (expand-file-name file-base pub-dir))
             (target-file (expand-file-name "index.html" target-dir)))
        (unless (file-directory-p target-dir)
          (make-directory target-dir t))
        (rename-file out-file target-file t)
        target-file))))

(defun ews-org-html-pretty-link-filter (text backend info)
  "Rewrite relative .html links to pretty URLs in TEXT for BACKEND using INFO.
Also converts relative images to root-relative paths.
When the backend is not 'html then keep the TEXT as-is."
  (if (org-export-derived-backend-p backend 'html)
      (cond
       ;; 1. Handle <a ... href="..."> hyperlinks
       ((string-match "<a\\([^>]+?\\)href=\"\\([^\"]+?\\)\"\\([^>]*>\\)" text)
        (let* ((pre (match-string 1 text))
               (href (match-string 2 text))
               (post (match-string 3 text))
               (body (substring text (match-end 0))))
          (if (and (not (string-match-p "^[a-z]+:" href))
                   (not (string-prefix-p "#" href))
                   (string-match "^\\(.*?\\)\\.html\\(#.*\\)?$" href))
              (let* ((path-part (match-string 1 href))
                     (anchor-part (or (match-string 2 href) ""))
                     (input-file (or (plist-get info :input-file)
                                     (org-element-property :path (plist-get info :parse-tree))
                                     buffer-file-name
                                     ""))
                     (current-dir (file-name-directory (expand-file-name input-file)))
                     (base-dir (ews-org-publish-base-dir info))
                     (target-abs (expand-file-name (concat path-part ".org") current-dir))
                     (rel-to-base (file-relative-name target-abs base-dir))
                     (pretty-path
                      (cond
                       ((string-equal rel-to-base "index.org") "/")
                       ((string-suffix-p "/index.org" rel-to-base)
                        (concat "/" (substring rel-to-base 0 (- (length rel-to-base) 9))))
                       ((string-equal rel-to-base "404.org") "/404.html")
                       (t (concat "/" (file-name-sans-extension rel-to-base) "/")))))
                (concat "<a" pre "href=\"" pretty-path anchor-part "\"" post body))
            text)))
       ;; 2. Handle <img ... src="..."> inline images
       ((string-match "<img\\([^>]+?\\)src=\"\\([^\"]+?\\)\"\\([^>]*>\\)" text)
        (let* ((pre (match-string 1 text))
               (src (match-string 2 text))
               (post (match-string 3 text))
               (body (substring text (match-end 0))))
          (if (and (not (string-match-p "^[a-z]+:" src))
                   (not (string-prefix-p "/" src)))
              (let* ((input-file (or (plist-get info :input-file)
                                     (org-element-property :path (plist-get info :parse-tree))
                                     buffer-file-name
                                     ""))
                     (current-dir (file-name-directory (expand-file-name input-file)))
                     (base-dir (ews-org-publish-base-dir info))
                     (target-abs (expand-file-name src current-dir))
                     (rel-to-base (file-relative-name target-abs base-dir))
                     (root-rel-src (concat "/" rel-to-base)))
                (concat "<img" pre "src=\"" root-rel-src "\"" post body))
            text)))

       (t text))
    text))

(defun ews-org-publish-generate-llms-txt (plist)
  "Generate standard llms.txt using publishing parameters in PLIST.
The llms.txt file provides information to help AI agents use a website.
Format in accordance with the specification on https://llmstxt.org/."
  (let* ((base-dir (expand-file-name (plist-get plist :base-directory)))
         (base-url (or (plist-get plist :base-url) ews-canonical-base-url))
	 (pub-dir (expand-file-name (plist-get plist :publishing-directory)))
         (output-file (expand-file-name "llms.txt" pub-dir))
         (all-files (when (file-directory-p base-dir)
                      (directory-files-recursively base-dir "\\.org$")))
	 (header (ews-file-to-string "templates/llms.txt"))
	 grouped)
    (unless (file-directory-p pub-dir)
      (make-directory pub-dir t))
    ;; Generate the list of content
    (dolist (file all-files)
      (let ((rel (file-relative-name file base-dir)))
        (unless (or (string-prefix-p "404" rel)
                    (string-equal rel "sitemap.org")
                    (string-equal rel "gemlog.org")
                    (ews-org-file-excluded-p file 'www))
          (let* ((parsed (ews-org-collect-file-keywords file '("TITLE" "DESCRIPTION")))
                 (title (car (cdr (assoc "TITLE" parsed))))
                 (desc (car (cdr (assoc "DESCRIPTION" parsed))))
                 (dir (file-name-directory rel))
                 (section (if dir (capitalize (directory-file-name dir)) "Optional"))
                 (pretty-slug (cond
                               ((string-equal rel "index.org") "")
                               ((string-suffix-p "/index.org" rel)
                                (substring rel 0 (- (length rel) 9)))
                               (t (concat (file-name-sans-extension rel) "/"))))
                 (url (concat (file-name-as-directory base-url) pretty-slug)))
            (push (list :title title :url url :desc desc :rel rel)
                  (alist-get section grouped nil nil #'string-equal))))))
    ;; Generate the file
    (with-temp-file output-file
      (insert header)
      (let ((sections (append (mapcar #'capitalize (ews-org-publish-category-dirs base-dir))
                              '("Optional"))))
	(dolist (sec sections)
	  (let ((items (nreverse (alist-get sec grouped nil nil #'string-equal))))
            (when items
              (insert (format "## %s\n\n" sec))
              (dolist (item items)
		(insert (format "- [%s](%s)%s\n"
				(plist-get item :title)
				(plist-get item :url)
				(if (plist-get item :desc)
                                    (format ": %s" (plist-get item :desc))
				  "")))))
            (insert "\n")))))
    (message "Generated llms.txt")))

(defun ews-org-publish-generate-sitemap-xml (plist)
  "Generate standard sitemap.xml from HTM files using project parameters in PLIST.
Sitemap in accodane with https://www.sitemaps.org/."
  (let* ((pub-dir (plist-get plist :publishing-directory))
	 (base-dir (expand-file-name (plist-get plist :base-directory)))
         (base-url (or (plist-get plist :base-url) ews-canonical-base-url))
         (sitemap-file (expand-file-name "sitemap.xml" pub-dir))
	 (toc-file (file-name-sans-extension (plist-get plist :sitemap-filename)))
	 (sections (append (ews-org-publish-category-dirs base-dir) '("theindex") (list toc-file)))
         (html-files (when (and pub-dir (file-directory-p pub-dir))
                       (directory-files-recursively pub-dir "\\.html$"))))
    (when html-files
      (with-temp-file sitemap-file
        (insert "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        (insert "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
        (dolist (file (sort html-files #'string<))
          (let* ((rel-file (file-relative-name file pub-dir)))
            ;; Exclude 404 error page
            (unless (string-prefix-p "404" (file-name-nondirectory rel-file))
              (let* ((file-base (file-name-sans-extension rel-file))
                     (is-root (string-equal rel-file "index.html"))
                     (is-index-sub (and (not is-root) (string-suffix-p "/index.html" rel-file)))
                     (dir-or-slug (when is-index-sub (substring rel-file 0 (- (length rel-file) 11))))
                     ;; Determine page role
                     (is-section (or is-root (member dir-or-slug sections)))
                     (changefreq (if is-section "weekly" "yearly"))
                     (priority (cond (is-root "1.0") (is-section "0.8") (t "0.7")))
                     (url-slug (cond
                                (is-root "")
                                (is-index-sub (concat dir-or-slug "/"))
                                (t (concat file-base "/"))))
                     (loc (concat (file-name-as-directory base-url) url-slug)))
                (insert "  <url>\n")
                (insert (format "    <loc>%s</loc>\n" loc))
                (insert (format "    <changefreq>%s</changefreq>\n" changefreq))
                (insert (format "    <priority>%s</priority>\n" priority))
                (insert "  </url>\n")))))
        (insert "</urlset>\n"))
      (message "Generated XML sitemap: %s" sitemap-file))))

;;; Category Feed Generator using webfeeder
(defun ews-webfeeder-date (html-file)
  "Extract article publication date for HTML-FILE from source or attributes."
  (let* ((project-dir (expand-file-name "www"))
         (base-dir (ews-org-publish-base-dir))
         (rel-html (file-relative-name html-file project-dir))
         (dir-or-slug (cond
                       ((string-suffix-p "/index.html" rel-html)
                        (substring rel-html 0 (- (length rel-html) 11)))
                       ((string-suffix-p ".html" rel-html)
                        (substring rel-html 0 (- (length rel-html) 5)))
                       (t nil)))
         (cand (when dir-or-slug (expand-file-name (concat dir-or-slug ".org") base-dir))))
    (if (and cand (file-exists-p cand))
        (let* ((kw (ews-org-collect-file-keywords cand '("DATE")))
               (raw-date (car (cdr (assoc "DATE" kw)))))
          (if (and raw-date (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" raw-date))
              (date-to-time (concat (match-string 1 raw-date) " 00:00:00"))
            (file-attribute-modification-time (file-attributes html-file))))
      (file-attribute-modification-time (file-attributes html-file)))))

(defun ews-org-publish-generate-category-feeds (plist)
  "Generate Atom feeds for all category subdirectories using webfeeder.
PLIST is the property list of the publishing project."
  (let* ((base-dir (expand-file-name (plist-get plist :base-directory)))
         (project-dir (expand-file-name (plist-get plist :publishing-directory)))
         (base-url (or (plist-get plist :base-url) ews-canonical-base-url))
         (site-name (plist-get plist :site-name))
         (categories (ews-org-publish-category-dirs base-dir)))
    (dolist (cat categories)
      (let* ((cat-pub-dir (expand-file-name cat project-dir))
             (cat-src-dir (expand-file-name cat base-dir))
             (cat-index (expand-file-name "index.org" cat-src-dir))
             (cat-url (concat (file-name-as-directory base-url) cat "/"))
             (meta (when (file-exists-p cat-index)
                     (ews-org-collect-file-keywords cat-index '("TITLE" "DESCRIPTION"))))
             (cat-title (or (car (cdr (assoc "TITLE" meta)))
                            (format "%s - %s" (capitalize cat) site-name)))
             (cat-desc (or (car (cdr (assoc "DESCRIPTION" meta)))
                           (format "%s articles on %s" (capitalize cat) site-name)))
             (all-html
              (when (file-directory-p cat-pub-dir)
                (directory-files-recursively cat-pub-dir "index\\.html$")))
             (article-html
              (seq-filter
               (lambda (f)
                 (not (string-equal f (expand-file-name "index.html" cat-pub-dir))))
               all-html))
             (rel-files
              (mapcar (lambda (f) (file-relative-name f project-dir)) article-html)))
        (let* ((webfeeder-date-function #'ews-webfeeder-date)
               (items (when rel-files
                        (webfeeder-html-files-to-items project-dir base-url rel-files))))
          (dolist (item items)
            (setf (webfeeder-item-url item)
                  (replace-regexp-in-string "index\\.html$" "" (webfeeder-item-url item)))
            (unless (webfeeder-item-author item)
              (setf (webfeeder-item-author item) user-full-name)))
          ;; Generate Atom feed
          (let ((atom-xml (webfeeder-make-atom
                           "atom.xml"
                           cat-url
                           items
                           :title cat-title
                           :subtitle cat-desc
                           :author user-full-name)))
            (unless (file-directory-p cat-pub-dir)
              (make-directory cat-pub-dir t))
            (with-temp-file (expand-file-name (format "%s/atom.xml" cat) project-dir)
              (insert atom-xml)))
          (message "Generated Atom feed for: %s (%d articles)" cat (length items)))))))

;;; Publishing Schedule Generator for Org-agenda
(defun ews-org-publish-generate-publishing-schedule (plist)
  "Generate publishing-schedule.org in project root from parameters in PLIST.
Lists unpublished posts and published TOC."
  (let* ((base-dir (expand-file-name (plist-get plist :base-directory)))
         (project-root (or (locate-dominating-file base-dir (plist-get plist :base-directory))
                           (expand-file-name ".")))
         (schedule-file (expand-file-name "publishing-schedule.org" project-root))
         (toc-file (expand-file-name (plist-get plist :sitemap-filename) base-dir))
         (all-files (when (file-directory-p base-dir)
                      (directory-files-recursively base-dir "\\.org$")))
         todo-items
         next-items)
    (dolist (file all-files)
      (let ((rel (file-relative-name file base-dir)))
        (when (and (not (member (file-name-nondirectory rel)
                                '("index.org" "toc.org" "theindex.org" "gemlog.org" "404.org" "about.org" "sitemap.org" "publishing-schedule.org")))
                   (ews-org-file-excluded-p file))
          (let* ((kw (ews-org-collect-file-keywords file '("TITLE" "DATE" "FILETAGS")))
                 (title (or (car (cdr (assoc "TITLE" kw))) (file-name-base file)))
                 (raw-date (car (cdr (assoc "DATE" kw))))
                 (tags (car (cdr (assoc "FILETAGS" kw))))
                 (tag-str (if (org-string-nw-p tags) (concat " " (string-trim tags)) ""))
                 (abs-path (expand-file-name file))
                 (date-match (and raw-date (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" raw-date)
                                  (match-string 1 raw-date))))
            (if date-match
                (let* ((time (date-to-time (concat date-match " 00:00:00")))
                       (ts (format-time-string "<%Y-%m-%d %a>" time)))
                  (push (list :date date-match
                              :entry (format "* TODO [[file:%s][%s]]%s\nDEADLINE: %s\n"
                                             abs-path title tag-str ts))
                        todo-items))
              (push (format "* NEXT [[file:%s][%s]]%s\n" abs-path title tag-str)
                    next-items))))))
    (setq todo-items (sort todo-items (lambda (a b) (string< (plist-get a :date) (plist-get b :date)))))
    ;; Insert published content in table of contents
    (let ((published-toc
           (when (file-exists-p toc-file)
             (with-temp-buffer
               (insert-file-contents toc-file)
               (goto-char (point-min))
               (while (and (not (eobp)) (looking-at-p "^[ \t]*#\\+"))
                 (forward-line 1))
               (while (and (not (eobp)) (looking-at-p "^[ \t]*$"))
                 (forward-line 1))
               (let ((body (buffer-substring-no-properties (point) (point-max))))
                 (string-trim
                  (replace-regexp-in-string
                   "\\[\\[file:\\([^/][^]]*\\)\\]"
                   (lambda (match)
                     (format "[[file:%s]"
                             (expand-file-name (match-string 1 match) base-dir)))
                   body)))))))
      ;; Construct agenda file
      (with-temp-file schedule-file
        (insert "#+title:    Publishing Schedule\n")
	(insert "#+date:     " (format-time-string "<%Y-%m-%d %a %H:%M>") "\n")
        (insert "#+todo:     TODO(t) NEXT(n) | DONE(d!)\n")
	(insert "#+category: www\n\n")
        (when todo-items
          (insert (mapconcat (lambda (x) (plist-get x :entry)) todo-items "\n"))
          (insert "\n"))
        (when next-items
          (insert (mapconcat #'identity (nreverse next-items) "\n"))
          (insert "\n"))
        (when (org-string-nw-p published-toc)
          (insert "* Published\n")
          (insert published-toc "\n"))))
    (message "Generated publishing schedule: %s" schedule-file)))

(provide 'publish-common)
;;; publish-common.el ends here
