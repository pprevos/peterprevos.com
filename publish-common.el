;;; publish-common.el --- Shared macros for publishing -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared package initialization, macros, article list generators,
;; and draft/future post filters across export backends.

;;; Code:

;; Initialize package sources
(require 'package)
(setq package-user-dir (expand-file-name "./.packages"))
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)

(unless package-archive-contents
  (ignore-errors (package-refresh-contents)))

;; Generic variables
(setq user-full-name "Peter Prevos"
      user-mail-address "peter@prevos.net")

(require 'org)
(require 'ox)
(require 'seq)

(defun ews-org-draft-p (draft-val)
  "Return t if DRAFT-VAL represents a non-nil draft status."
  (and draft-val
       (let ((v (downcase (string-trim draft-val))))
         (and (not (string-empty-p v))
              (not (member v '("nil" "no" "false" "0")))))))

(defun ews-org-future-p (date-val)
  "Return t if DATE-VAL represents a date in the future."
  (when (and date-val (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" date-val))
    (let ((date-str (match-string 1 date-val))
          (today-str (format-time-string "%Y-%m-%d")))
      (string> date-str today-str))))

(defun ews-org-file-excluded-p (file)
  "Return t if FILE has non-nil #+DRAFT: or a future #+DATE:."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    (let* ((parsed (org-collect-keywords '("DATE" "DRAFT")))
           (draft (car (cdr (assoc "DRAFT" parsed))))
           (date (car (cdr (assoc "DATE" parsed)))))
      (or (ews-org-draft-p draft)
          (ews-org-future-p date)))))

(defun ews-org-publish-exclude-regex (&optional base-dir)
  "Return a regexp matching drafts, future-dated files, and .*_draft patterns."
  (let* ((dir (expand-file-name (or base-dir "content")))
         (all-files (when (file-directory-p dir)
                      (directory-files-recursively dir "\\.org$")))
         (excluded-rel-files
          (seq-filter
           (lambda (rel)
             (let ((full (expand-file-name rel dir)))
               (ews-org-file-excluded-p full)))
           (mapcar (lambda (f) (file-relative-name f dir)) all-files))))
    (if excluded-rel-files
        (concat ".*_draft\\|"
                (mapconcat (lambda (f) (concat "^" (regexp-quote f) "$"))
                           excluded-rel-files
                           "\\|"))
      ".*_draft")))

(defun ews-org-publish-get-directory-articles ()
  "Collect metadata for all non-draft, non-future Org articles in current directory."
  (let* ((current-file (when buffer-file-name
                         (file-name-nondirectory buffer-file-name)))
         (files (seq-remove (lambda (f) (string-equal f current-file))
                            (directory-files default-directory nil "\\.org$")))
         articles)
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (org-mode)
        (let* ((parsed (org-collect-keywords '("TITLE" "DATE" "DESCRIPTION" "DRAFT")))
               (draft (car (cdr (assoc "DRAFT" parsed))))
               (timestamp (car (cdr (assoc "DATE" parsed)))))
          (unless (or (ews-org-draft-p draft)
                      (ews-org-future-p timestamp))
            (let* ((title (or (car (cdr (assoc "TITLE" parsed)))
                              (file-name-nondirectory file)))
                   (date (if (and timestamp (>= (length timestamp) 11))
                             (substring timestamp 1 11)
                           ""))
                   (desc (car (cdr (assoc "DESCRIPTION" parsed)))))
              (push (list :file file
                          :title title
                          :date date
                          :description desc)
                    articles))))))
    ;; Sort reverse-chronologically by date
    (sort articles
          (lambda (a b)
            (string> (plist-get a :date) (plist-get b :date))))))

(defun ews-org-publish-list-files-html (articles)
  "Format ARTICLES as Org list items for HTML export."
  (mapconcat
   (lambda (art)
     (let* ((file (plist-get art :file))
            (title (plist-get art :title))
            (date (plist-get art :date))
            (date-str (if (org-string-nw-p date) (format "%s: " date) ""))
            (desc (plist-get art :description))
            (desc-str (if (org-string-nw-p desc) (format ": %s" desc) "")))
       (format "- %s[[file:%s][%s]]%s" date-str file title desc-str)))
   articles
   "\n"))

(defun ews-org-publish-list-files-gemini (articles)
  "Format ARTICLES as Gemtext link lines for Gemini export."
  (concat
   "#+begin_export gemini\n"
   (mapconcat
    (lambda (art)
      (let* ((file (plist-get art :file))
             (gmi-file (concat (file-name-sans-extension file) ".gmi"))
             (title (plist-get art :title))
             (date (plist-get art :date))
             (date-str (if (org-string-nw-p date) (format "%s " date) ""))
             (desc (plist-get art :description))
             (desc-str (if (org-string-nw-p desc) (format ": %s" desc) "")))
        (format "=> %s %s%s%s" gmi-file date-str title desc-str)))
    articles
    "\n")
   "\n#+end_export"))

(defun ews-org-publish-list-files ()
  "Create a date-sorted list of links to articles based on current export backend."
  (let ((articles (ews-org-publish-get-directory-articles)))
    (pcase org-export-current-backend
      ('gemini (ews-org-publish-list-files-gemini articles))
      ('html   (ews-org-publish-list-files-html articles))
      (_       (ews-org-publish-list-files-html articles)))))

;; Register global macro and bepoke options
(with-eval-after-load 'ox
  (add-to-list 'org-export-global-macros
               '("list-files" . "(eval (ews-org-publish-list-files))"))
  (add-to-list 'org-export-options-alist
               '(:with-meta nil "meta" nil)))

;;; Word Count & Auto Subtitle
(defun ews-org-word-count-buffer ()
  "Count words in the current Org buffer, ignoring keywords and drawers."
  (let ((count 0))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "\\b[[:alnum:]]+\\b" nil t)
        (unless (save-excursion
                  (beginning-of-line)
                  (looking-at-p "^[ \t]*\\(#\\+\\|:\\)"))
          (setq count (1+ count)))))
    count))

(defun ews-org-get-page-meta (info)
  "Extract author, formatted date, word count, and reading time for INFO."
  (let* ((author (or (org-export-data (plist-get info :author) info) user-full-name))
         (raw-date (plist-get info :date))
         (date (if (and raw-date (consp raw-date) (eq (org-element-type (car raw-date)) 'timestamp))
                   (string-trim (org-timestamp-format (car raw-date) "%e %B %Y"))
                 (if raw-date (org-export-data raw-date info) "")))
         (words (ews-org-word-count-buffer))
         (reading-time (max 1 (ceiling (/ (float words) 200)))))
    (list :author author :date date :words words :reading-time reading-time)))

(defun ews-org-html-auto-subtitle (tree backend info)
  "Construct a two-line subtitle when no #+SUBTITLE exists and meta:t is set."
  (when (and (org-export-derived-backend-p backend 'html)
             (not (plist-get info :subtitle))
             (plist-get info :with-meta))
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
  "Inject single-line metadata below title in Gemini OUTPUT when meta:t is set."
  (if (and (org-export-derived-backend-p backend 'gemini)
           (not (plist-get info :subtitle))
           (plist-get info :with-meta))
      (let* ((meta (ews-org-get-page-meta info))
             (author (plist-get meta :author))
             (date (plist-get meta :date))
             (words (plist-get meta :words))
             (reading-time (plist-get meta :reading-time))
             (parts (delq nil
                          (list (concat "✎ " author)
                                (when (org-string-nw-p date) (concat " 🗓︎ " date))
                                (format " ⧗ %d words (%d min read)" words reading-time))))
             (meta-line (concat (string-join parts) "\n\n")))
        (if (string-match "^# \\(.*?\\)\n\n" output)
            (replace-match (concat (match-string 0 output) meta-line) t t output)
          (concat meta-line output)))
    output))

;;; Pretty URLs Implementation
(defun ews-org-publish-to-pretty-html (plist filename pub-dir)
  "Publish an Org file and convert non-index HTML files to subfolder/index.html."
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
  "Rewrite relative .html links to pretty URLs and relative images to root-relative paths."
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
                     (project-root (or (locate-dominating-file current-dir "content")
                                       default-directory))
                     (base-dir (file-name-as-directory (expand-file-name (or (plist-get info :base-directory) "content") project-root)))
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
                     (project-root (or (locate-dominating-file current-dir "content")
                                       default-directory))
                     (base-dir (file-name-as-directory (expand-file-name (or (plist-get info :base-directory) "content") project-root)))
                     (target-abs (expand-file-name src current-dir))
                     (rel-to-base (file-relative-name target-abs base-dir))
                     (root-rel-src (concat "/" rel-to-base)))
                (concat "<img" pre "src=\"" root-rel-src "\"" post body))
            text)))

       (t text))
    text))

;;; LLMs.txt Generator (Preparation Function)
(defun ews-org-publish-generate-llms-txt (plist)
  "Generate standard llms.txt in static-www/ directory prior to publishing."
  (let* ((base-dir (expand-file-name (or (plist-get plist :base-directory) "content")))
         (base-url (or (plist-get plist :base-url) "https://peterprevos.com/"))
         (static-dir (expand-file-name "static-www"))
         (output-file (expand-file-name "llms.txt" static-dir))
         (all-files (when (file-directory-p base-dir)
                      (directory-files-recursively base-dir "\\.org$")))
         grouped)
    (unless (file-directory-p static-dir)
      (make-directory static-dir t))
    (dolist (f all-files)
      (let ((rel (file-relative-name f base-dir)))
        ;; Exclude error pages, sitemaps, drafts, and future articles
        (unless (or (string-prefix-p "404" rel)
                    (string-equal rel "sitemap.org")
                    (string-equal rel "gemlog.org")
                    (ews-org-file-excluded-p f))
          (with-temp-buffer
            (insert-file-contents f)
            (org-mode)
            (let* ((parsed (org-collect-keywords '("TITLE" "DESCRIPTION")))
                   (title (or (car (cdr (assoc "TITLE" parsed))) (file-name-base f)))
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
                    (alist-get section grouped nil nil #'string-equal)))))))
    (with-temp-file output-file
      (insert "# The Horizon of Reason\n\n")
      (insert "> The Horizon of Reason by Peter Prevos explores the limits of rationality through philosophical essays, digital asceticism, and creative worldbuilding.\n\n")
      (insert "Curated index of published pages for LLMs and AI agents.\n\n")
      (dolist (sec '("Praxis" "Logos" "Mythos" "Optional"))
        (let ((items (nreverse (alist-get sec grouped nil nil #'string-equal))))
          (when items
            (insert (format "## %s\n\n" sec))
            (dolist (item items)
              (let ((desc-str (if (plist-get item :desc)
                                  (format ": %s" (plist-get item :desc))
                                "")))
                (insert (format "- [%s](%s)%s\n"
                                (plist-get item :title)
                                (plist-get item :url)
                                desc-str))))
            (insert "\n")))))
    (message "Generated LLMs.txt: %s" output-file)))

;;; XML Sitemap Generator
(defun ews-org-publish-generate-sitemap-xml (plist)
  "Generate standard sitemap.xml in :publishing-directory with lastmod, changefreq, and priority."
  (let* ((pub-dir (plist-get plist :publishing-directory))
         (base-dir (plist-get plist :base-directory))
         (base-url (or (plist-get plist :base-url) "https://peterprevos.com/"))
         (sitemap-file (expand-file-name "sitemap.xml" pub-dir))
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
                     ;; Resolve actual source .org file
                     (cand-1 (expand-file-name (concat file-base ".org") base-dir))
                     (cand-2 (when dir-or-slug (expand-file-name (concat dir-or-slug ".org") base-dir)))
                     (org-file (cond
                                ((file-exists-p cand-1) cand-1)
                                ((and cand-2 (file-exists-p cand-2)) cand-2)
                                (t nil)))
                     ;; Determine page role
                     (is-section (or (member dir-or-slug '("logos" "mythos" "praxis" "thauma" "toc" "theindex"))
                                     (and org-file (string-suffix-p "/index.org" org-file))))
                     (default-cf (cond (is-root "weekly") (is-section "weekly") (t "monthly")))
                     (default-pr (cond (is-root "1.0") (is-section "0.8") (t "0.7")))
                     lastmod changefreq priority)

                ;; Read source .org file keywords if it exists
                (if (and org-file (file-exists-p org-file))
                    (with-temp-buffer
                      (insert-file-contents org-file)
                      (org-mode)
                      (let* ((kw (org-collect-keywords '("LASTMOD" "DATE" "CHANGEFREQ" "PRIORITY")))
                             (raw-mod (or (car (cdr (assoc "LASTMOD" kw)))
                                          (car (cdr (assoc "DATE" kw))))))
                        ;; Date
                        (setq lastmod
                              (if (and raw-mod (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" raw-mod))
                                  (match-string 1 raw-mod)
                                (format-time-string "%Y-%m-%d" (file-attribute-modification-time (file-attributes file)))))
                        ;; Changefreq & Priority
                        (setq changefreq (or (car (cdr (assoc "CHANGEFREQ" kw))) default-cf))
                        (setq priority (or (car (cdr (assoc "PRIORITY" kw))) default-pr))))
                  ;; Fallback
                  (setq lastmod (format-time-string "%Y-%m-%d" (file-attribute-modification-time (file-attributes file))))
                  (setq changefreq default-cf)
                  (setq priority default-pr))

                ;; Canonical URL
                (let* ((url-slug (cond
                                  (is-root "")
                                  (is-index-sub (concat dir-or-slug "/"))
                                  (t (concat file-base "/"))))
                       (loc (concat (file-name-as-directory base-url) url-slug)))
                  (insert "  <url>\n")
                  (insert (format "    <loc>%s</loc>\n" loc))
                  (insert (format "    <lastmod>%s</lastmod>\n" lastmod))
                  (insert (format "    <changefreq>%s</changefreq>\n" changefreq))
                  (insert (format "    <priority>%s</priority>\n" priority))
                  (insert "  </url>\n"))))))
        (insert "</urlset>\n"))
      (message "Generated XML sitemap: %s" sitemap-file))))

;;; Publishing Schedule Generator for Org-agenda
(defun ews-org-publish-generate-publishing-schedule (plist)
  "Generate publishing-schedule.org in project root listing unpublished posts and published TOC."
  (let* ((base-dir (expand-file-name (or (plist-get plist :base-directory) "content")))
         (project-root (or (locate-dominating-file base-dir "content")
                           (expand-file-name ".")))
         (schedule-file (expand-file-name "publishing-schedule.org" project-root))
         (toc-file (expand-file-name (or (plist-get plist :sitemap-filename) "toc.org") base-dir))
         (exclude-regex (or (plist-get plist :exclude)
                            (ews-org-publish-exclude-regex base-dir)))
         (all-files (when (file-directory-p base-dir)
                      (directory-files-recursively base-dir "\\.org$")))
         todo-items
         next-items)
    (dolist (f all-files)
      (let ((rel (file-relative-name f base-dir)))
        (when (and exclude-regex
                   (string-match-p exclude-regex rel)
                   (not (member (file-name-nondirectory rel)
                                '("index.org" "toc.org" "theindex.org" "gemlog.org" "404.org" "about.org" "sitemap.org" "publishing-schedule.org"))))
          (with-temp-buffer
            (insert-file-contents f)
            (org-mode)
            (let* ((kw (org-collect-keywords '("TITLE" "DATE" "FILETAGS")))
                   (title (or (car (cdr (assoc "TITLE" kw))) (file-name-base f)))
                   (raw-date (car (cdr (assoc "DATE" kw))))
                   (tags (car (cdr (assoc "FILETAGS" kw))))
                   (tag-str (if (org-string-nw-p tags) (concat " " (string-trim tags)) ""))
                   (rel-path (file-relative-name f project-root))
                   (date-match (and raw-date (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" raw-date)
                                    (match-string 1 raw-date))))
              (if date-match
                  (let* ((time (date-to-time (concat date-match " 00:00:00")))
                         (ts (format-time-string "<%Y-%m-%d %a>" time)))
                    (push (list :date date-match
                                :entry (format "* TODO [[file:%s][%s]]%s\nDEADLINE: %s\n"
                                               rel-path title tag-str ts))
                          todo-items))
                (push (format "* NEXT [[file:%s][%s]]%s\n" rel-path title tag-str)
                      next-items)))))))
    (setq todo-items (sort todo-items (lambda (a b) (string< (plist-get a :date) (plist-get b :date)))))
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
                 (string-trim (replace-regexp-in-string "\\[\\[file:\\([^/]\\)" "[[file:content/\\1" body)))))))
      (with-temp-file schedule-file
        (insert "#+title: Publishing Schedule\n")
        (insert "#+todo: TODO(t) NEXT(n) WAIT(w@/!) PROJECT(p) | DONE(d!) CANCELED(c@/!)\n\n")
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
