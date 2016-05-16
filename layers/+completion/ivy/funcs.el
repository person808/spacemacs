;;; funcs.el --- Ivy Layer functions File for Spacemacs
;;
;; Copyright (c) 2012-2016 Sylvain Benner & Contributors
;;
;; Author: Sylvain Benner <sylvain.benner@gmail.com>
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3


;; Counsel

;; async

(defvar spacemacs--counsel-initial-cands-shown nil)

(defun spacemacs//counsel-async-command (cmd)
  (let* ((counsel--process " *counsel*")
         (proc (get-process counsel--process))
         (buff (get-buffer counsel--process)))
    (when proc
      (delete-process proc))
    (when buff
      (kill-buffer buff))
    (setq proc (start-process-shell-command
                counsel--process
                counsel--process
                cmd))
    (setq spacemacs--counsel-initial-cands-shown nil)
    (setq counsel--async-time (current-time))
    (set-process-sentinel proc #'counsel--async-sentinel)
    (set-process-filter proc #'spacemacs//counsel-async-filter)))

(defun spacemacs//counsel-async-filter (process str)
    (with-current-buffer (process-buffer process)
      (insert str))
    (when (or (null spacemacs--counsel-initial-cands-shown)
              (time-less-p
               ;; 0.5s
               '(0 0 500000 0)
               (time-since counsel--async-time)))
      (let (size display-now)
        (with-current-buffer (process-buffer process)
          (goto-char (point-min))
          (setq size (- (buffer-size) (forward-line (buffer-size))))
          (when (and (null spacemacs--counsel-initial-cands-shown)
                     (> size spacemacs--counsel-initial-number-cand))
            (setq ivy--all-candidates
                  (split-string (buffer-string) "\n" t))
            (setq display-now t)
            (setq spacemacs--counsel-initial-cands-shown t)))
        (let ((ivy--prompt
               (format (ivy-state-prompt ivy-last)
                       size)))
          (if display-now
              (ivy--insert-minibuffer
               (ivy--format ivy--all-candidates))
            (ivy--insert-prompt))))
      (setq counsel--async-time (current-time))))

;; search

(defvar spacemacs--counsel-search-cmd)

;; see `counsel-ag-function'
(defun spacemacs//make-counsel-search-function (tool)
    (lexical-let ((base-cmd
                   (cdr (assoc-string tool spacemacs--counsel-commands))))
      (lambda (string &optional _pred &rest _unused)
        "Grep in the current directory for STRING."
        (if (< (length string) 3)
            (counsel-more-chars 3)
          (let* ((default-directory counsel--git-grep-dir)
                 (args (if (string-match-p " -- " string)
                           (let ((split (split-string string " -- ")))
                             (prog1 (pop split)
                               (setq string (mapconcat #'identity split " -- "))))
                         ""))
                 (regex (counsel-unquote-regex-parens
                         (setq ivy--old-re
                               (ivy--regex string)))))
            (setq spacemacs--counsel-search-cmd (format base-cmd args regex))
            (spacemacs//counsel-async-command spacemacs--counsel-search-cmd)
            nil)))))

;; see `counsel-ag'
(defun spacemacs/counsel-search
      (&optional tools use-initial-input initial-directory)
    "Search using the first available tool in TOOLS. Default tool
to try is grep. If INPUT is non nil, use the region or the symbol
around point as the initial input. If DIR is non nil start in
that directory."
    (interactive)
    (require 'counsel)
    (letf* ((initial-input (if use-initial-input
                               (if (region-active-p)
                                   (buffer-substring-no-properties
                                    (region-beginning) (region-end))
                                 (thing-at-point 'symbol t))
                             ""))
            (tool (catch 'tool
                    (dolist (tool tools)
                      (when (and (assoc-string tool spacemacs--counsel-commands)
                                 (executable-find tool))
                        (throw 'tool tool)))
                    (throw 'tool "grep"))))
      (setq counsel--git-grep-dir
            (or initial-directory
                (read-directory-name "Start from directory: ")))
      (ivy-read
       (concat ivy-count-format
               (format "%s from [%s]: "
                       tool
                       (if (< (length counsel--git-grep-dir)
                              spacemacs--counsel-search-max-path-length)
                           counsel--git-grep-dir
                         (concat
                          "..." (substring counsel--git-grep-dir
                                           (- (length counsel--git-grep-dir)
                                              spacemacs--counsel-search-max-path-length)
                                           (length counsel--git-grep-dir))))))
       (spacemacs//make-counsel-search-function tool)
       :initial-input (rxt-quote-pcre initial-input)
       :dynamic-collection t
       :history 'counsel-git-grep-history
       :action #'counsel-git-grep-action
       :caller 'spacemacs/counsel-search
       :unwind (lambda ()
                 (counsel-delete-process)
                 (swiper--cleanup)))))

;; Define search functions for each tool
(cl-loop
   for (tools tool-name) in '((dotspacemacs-search-tools "auto")
                              ((list "ag") "ag")
                              ((list "pt") "pt")
                              ((list "ack") "ack")
                              ((list "grep") "grep"))
   do
   (eval
    `(progn
       (defun ,(intern (format "spacemacs/search-%s" tool-name)) ()
         ,(format
           "Use `spacemacs/counsel-search' to search in the current
 directory with %s." (if (string= tool-name "auto")
                         "a tool selected from `dotspacemacs-search-tools'."
                       tool-name))
         (interactive)
         (spacemacs/counsel-search ,tools))
       (defun ,(intern (format "spacemacs/search-%s-region-or-symbol"
                               tool-name)) ()
         ,(format
           "Use `spacemacs/counsel-search' to search for
 the selected region or the symbol around point in the current
 directory with %s." (if (string= tool-name "auto")
                         "a tool selected from `dotspacemacs-search-tools'."
                       tool-name))
         (interactive)
         (spacemacs/counsel-search ,tools t))
       (defun ,(intern (format "spacemacs/search-project-%s" tool-name)) ()
         ,(format
           "Use `spacemacs/counsel-search' to search in the current
 project with %s." (if (string= tool-name "auto")
                       "a tool selected from `dotspacemacs-search-tools'."
                     tool-name))
         (interactive)
         (spacemacs/counsel-search ,tools nil (projectile-project-root)))
       (defun ,(intern (format "spacemacs/search-project-%s-region-or-symbol"
                               tool-name)) ()
         ,(format
           "Use `spacemacs/counsel-search' to search for
 the selected region or the symbol around point in the current
 project with %s." (if (string= tool-name "auto")
                       "a tool selected from `dotspacemacs-search-tools'."
                     tool-name))
         (interactive)
         (spacemacs/counsel-search ,tools t (projectile-project-root))))))

(defun spacemacs/counsel-git-grep-region-or-symbol ()
  "Use `counsel-git-grep' to search for the selected region or
 the symbol around point in the current project with git grep."
  (interactive)
  (let ((input (if (region-active-p)
                   (buffer-substring-no-properties
                    (region-beginning) (region-end))
                 (thing-at-point 'symbol t))))
    (counsel-git-grep nil input)))

(defun spacemacs/counsel-search-docs ()
  "Search spacemacs docs using `spacemacs/counsel-search'"
  (interactive)
  (spacemacs/counsel-search dotspacemacs-search-tools
                            nil spacemacs-docs-directory))

(defun spacemacs//counsel-occur ()
  "Generate a custom occur buffer for `counsel-git-grep'."
  (ivy-occur-grep-mode)
  (setq default-directory counsel--git-grep-dir)
  (let ((cands ivy--old-cands))
    ;; Need precise number of header lines for `wgrep' to work.
    (insert (format "-*- mode:grep; default-directory: %S -*-\n\n\n"
                    default-directory))
    (insert (format "%d candidates:\n" (length cands)))
    (ivy--occur-insert-lines
     (mapcar
      (lambda (cand) (concat "./" cand))
      ivy--old-cands))))

(defun spacemacs/counsel-up-directory-no-error ()
  "`counsel-up-directory' ignoring errors."
  (interactive)
  (ignore-errors
    (call-interactively 'counsel-up-directory)))

(when (configuration-layer/package-usedp 'counsel)
  (with-eval-after-load 'counsel
    (defun spacemacs/describe-mode ()
      "Dummy wrapper to prevent an key binding error from helm.

By default the emacs leader is M-m, turns out that Helm does this:
   (cl-dolist (k (where-is-internal 'describe-mode global-map))
        (define-key map k 'helm-help))
after doing this:
   (define-key map (kbd \"M-m\") 'helm-toggle-all-marks)
So when Helm is loaded we get the error:
   Key sequence M-m h d m starts with non-prefix key M-m

To prevent this error we just wrap `describe-mode' to defeat the
 Helm hack."
      (interactive)
      (call-interactively 'describe-mode))))


;; Ivy

(defun spacemacs//ivy-command-not-implemented-yet (key)
  (lexical-let ((-key key))
    (spacemacs/set-leader-keys
      -key (lambda ()
             (interactive)
             (message (concat "The command usually bound to %s %s has "
                              "not been implemented for the `ivy' layer yet.")
                      dotspacemacs-leader-key -key)))))

(defun spacemacs/ivy-available-repls ()
  "Show available repls."
  (interactive)
  (ivy-read "Repls: "
            (mapcar #'car spacemacs-repl-list)
            :action (lambda (candidate)
                      (let ((repl (cdr (assoc candidate spacemacs-repl-list))))
                        (require (car repl))
                        (call-interactively (cdr repl))))))

;; perspectives

(defun spacemacs/ivy-perspectives ()
  "Control Panel for perspectives. Has many actions.
If match is found
\(default) Select perspective
c: Close Perspective(s) <- mark with C-SPC to close more than one-window
k: Kill Perspective(s)

If match is not found
<enter> Creates perspective

Closing doesn't kill buffers inside the perspective while killing
perspectives does."
  (interactive)
  (ivy-read "Perspective: "
            (persp-names)
            :caller 'spacemacs/ivy-perspectives
            :action (lambda (name)
                      (let ((persp-reset-windows-on-nil-window-conf t))
                        (persp-switch name)
                        (unless
                            (member name
                                    (persp-names-current-frame-fast-ordered))
                          (spacemacs/home))))))

(defun spacemacs/ivy-persp-buffer ()
  "Switch to perspective buffer using ivy."
  (interactive)
  (let (ivy-use-virtual-buffers)
    (with-persp-buffer-list ()
                            (call-interactively 'ivy-switch-buffer))))

(defun spacemacs/ivy-persp-close-other ()
  "Kills perspectives without killing the buffers"
  (interactive)
  (ivy-read (format "Close perspective [current %s]: "
                    (spacemacs//current-layout-name))
            (persp-names)
            :action 'persp-kill-without-buffers))

(defun spacemacs/ivy-persp-kill-other ()
  "Kills perspectives with all their buffers"
  (interactive)
  (ivy-read (format "Kill perspective [current %s]: "
                    (spacemacs//current-layout-name))
            (persp-names)
            :action 'persp-kill))


;; Swiper

(defun spacemacs/swiper-region-or-symbol ()
  "Run `swiper' with the selected region or the symbol
around point as the initial input."
  (interactive)
  (let ((input (if (region-active-p)
                   (buffer-substring-no-properties
                    (region-beginning) (region-end))
                 (thing-at-point 'symbol t))))
    (swiper input)))

(defun spacemacs/swiper-all-region-or-symbol ()
  "Run `swiper-all' with the selected region or the symbol
around point as the initial input."
  (interactive)
  (ivy-read "Swiper: " (swiper--multi-candidates
                        (cl-remove-if-not
                         #'buffer-file-name
                         (buffer-list)))
            :initial-input (if (region-active-p)
                               (buffer-substring-no-properties
                                (region-beginning) (region-end))
                             (thing-at-point 'symbol t))
            :action 'swiper-multi-action-2
            :unwind #'swiper--cleanup
            :caller 'swiper-multi))