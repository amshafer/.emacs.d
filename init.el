;;; -*-emacs-lisp-*-
;;;

;;; to get colors to work, color-theme-* directory package should be 
;;; in ~/.emacs.d   - so should xcscope

; commonly used stuff

;; Added by Package.el.  This must come before configurations of
;; installed packages.  Don't delete this line.  If you don't want it,
;; just comment it out by adding a semicolon to the start of the line.
;; You may delete these explanatory comments.
(package-initialize)

(global-set-key (kbd "C-u") 'undo-only)
(global-set-key (kbd "M-1") 'executable-interpret)
(global-set-key (kbd "M-3") 'replace-string)
(global-set-key (kbd "M-2") 'eval-buffer)
(global-set-key (kbd "M-e") 'call-last-kbd-macro)

;; movement aliases
(global-set-key (kbd "M-[") 'backward-paragraph)
(global-set-key (kbd "M-]") 'forward-paragraph)

; multi buffer comfort
(global-set-key (kbd "M-n") 'next-buffer)
(global-set-key (kbd "M-p") 'previous-buffer)
(global-set-key (kbd "C-o") 'other-window)
(global-set-key (kbd "M-e") 'end-of-buffer)
(global-set-key (kbd "M-a") 'beginning-of-buffer)

; reopen buffers from last session
;; use only one desktop-------------------------------
(setq desktop-path '("~/.emacs.d/"))
(setq desktop-dirname "~/.emacs.d/")
(setq desktop-base-file-name "emacs-desktop")
(setq desktop-save t)

;; remove desktop after it's been read
(add-hook 'desktop-after-read-hook
	  '(lambda ()
	     ;; desktop-remove clears desktop-dirname
	     (setq desktop-dirname-tmp desktop-dirname)
	     (desktop-remove)
	     (setq desktop-dirname desktop-dirname-tmp)))

(defun saved-session ()
  (file-exists-p (concat desktop-dirname "/" desktop-base-file-name)))

;; use session-restore to restore the desktop manually
(defun session-restore ()
  "Restore a saved emacs session."
  (interactive)
  (if (saved-session)
      (desktop-read)
    (message "No desktop found.")))

(defun session-save ()
  "Save an emacs session."
	    (desktop-save-in-desktop-dir))

;; use session-save to save the desktop manually
(add-hook 'auto-save-hook
	  '(lambda ()
	    "Save an emacs session."
	    (desktop-save-in-desktop-dir)))

;; ask user whether to restore desktop at start-up
(add-hook 'after-init-hook
	  '(lambda ()
	     (if (saved-session)
		 (if (y-or-n-p "Restore desktop? ")
		     (session-restore)))))
;;;;;;----------------------------------------------

;; C code formatting
(setq c-default-style "bsd")

;; tramp should let zsh know that we are not a normal
;; user. Tramp needs this to work
(setq tramp-terminal-type "tramp")

;; disable toolbar
(menu-bar-mode -1)
(tool-bar-mode -1)

;; set a python interpreter for python mode
(setq python-shell-interpreter "/usr/bin/env python3.7")

;; set a delay so we only close one buffer
(defvar *timed-kill-buffer-var* t
  "can we switch?")

(defun timed-kill-buffer ()
  (interactive)
  (message "custom prev: *timed-kill-buffer-var*=%s" *timed-kill-buffer-var*)
  (when *timed-kill-buffer-var*
    (previous-buffer)
    (setq *timed-kill-buffer-var* nil)
    (run-at-time "1 sec" nil (lambda ()
                               (setq *timed-kill-buffer-var* t)))))
(global-set-key [triple-wheel-left] 'timed-kill-buffer)

(setq ring-bell-function 'ignore)

;; cscope support
(add-to-list 'load-path "~/.emacs.d/cscope")
(require 'xcscope)
(cscope-setup)

;; cscope keybindings
(global-set-key (kbd "C-c C-f") 'cscope-find-called-functions)
(global-set-key (kbd "C-c i") 'cscope-find-files-including-file)
(global-set-key (kbd "C-c c") 'cscope-find-functions-calling-this-function)
(global-set-key (kbd "C-c g") 'cscope-find-global-definition)
(global-set-key (kbd "C-c f") 'cscope-find-this-file)
(global-set-key (kbd "C-c t") 'cscope-find-this-text-string)
(global-set-key (kbd "C-c s") 'cscope-find-this-symbol)
(global-set-key (kbd "C-c p") 'cscope-pop-mark)

;;;; notmuch for email
(add-to-list 'load-path "/usr/local/share/emacs/site-lisp/")
(setenv "PATH" (concat (getenv "PATH") ":/usr/local/bin"))
(add-to-list 'exec-path "/usr/local/bin/")
(add-to-list 'exec-path "/usr/bin/")
(autoload 'notmuch "notmuch" "notmuch mail" t)
(require 'notmuch)

(defun ashafer/notmuch-remote-setup (sockname)
  (setq notmuch-command "/home/ashafer/bin/remote-notmuch")
  (setenv "REMOTE_NOTMUCH_SSHCTRL_SOCK" sockname))

;; press M-4 to reconnect to notmuch
(global-set-key (kbd "M-4") (lambda () (interactive)(call-process "~/bin/mc")) )

(ashafer/notmuch-remote-setup "master-notmuch@remote:22")

(require 'notmuch) ; loads notmuch package
(setq message-kill-buffer-on-exit t) ; kill buffer after sending mail)
(setq mail-specify-envelope-from t) ; Settings to work with msmtp
(setq message-sendmail-envelope-from 'header)
(setq mail-envelope-from 'header)
(setq mail-host-address "triplebuff.com")

;;;; notmuch tag shortcuts

;; mark spam
(define-key notmuch-search-mode-map (kbd "C-k")
      (lambda ()
        "toggle deleted tag for message"
        (interactive)
        (if (member "spam" (notmuch-search-get-tags))
            (notmuch-search-tag (list "-spam" "-inbox" "-unread"))
          (notmuch-search-tag (list "+spam" "-inbox" "-unread")))
	(next-line)
      )
)

;; mark deleted
(define-key notmuch-search-mode-map (kbd "C-d")
      (lambda ()
        "toggle deleted tag for message"
        (interactive)
        (if (member "deleted" (notmuch-search-get-tags))
            (notmuch-search-tag (list "-deleted" "-inbox" "-unread"))
          (notmuch-search-tag (list "+deleted" "-inbox" "-unread")))
	(next-line)
      )
)

;; mark unread
(define-key notmuch-search-mode-map (kbd "C-u")
      (lambda ()
        "toggle deleted tag for message"
        (interactive)
        (if (member "unread" (notmuch-search-get-tags))
            (notmuch-search-tag (list "-unread" "-inbox"))
          (notmuch-search-tag (list "+unread" "-inbox")))
	(next-line)
      )
)

;; mark bsd
(define-key notmuch-search-mode-map (kbd "C-i")
      (lambda ()
        "toggle deleted tag for message"
        (interactive)
	(notmuch-search-tag (list "-inbox" "-unread"))
	(next-line)
      )
)

;;;; set email sender

;; This is needed to allow msmtp to do its magic:
(setq message-sendmail-f-is-evil 't)

;;need to tell msmtp which account we're using
(setq message-sendmail-extra-arguments '("--read-envelope-from"))
;; with Emacs 23.1, you have to set this explicitly (in MS Windows)
;; otherwise it tries to send through OS associated mail client
(setq message-send-mail-function 'message-send-mail-with-sendmail)
;; we substitute sendmail with msmtp
(setq sendmail-program "~/bin/sendmail-remote.sh")
;; you might want to set the following too
;(setq user-full-name "Austin Shafer")
(setq notmuch-fcc-dirs "Sent")

;;;; Actual themes
(add-to-list 'load-path "~/.emacs.d/lisp")
;; rust format mode
(autoload 'rust-mode "rust-mode" nil t)
(add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-mode))

;(load-theme 'silkworm t)
(load-theme 'spacemacs-dark t)
;(load-theme 'dracula t)
;(load-theme 'oceanic t)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(color-theme-directory (quote ("~/.emacs.d/color-theme-6.6.0/")))
 '(custom-menu-nesting 0)
 '(custom-menu-order-groups nil)
 '(custom-safe-themes
   (quote
    ("fa2b58bb98b62c3b8cf3b6f02f058ef7827a8e497125de0254f56e373abee088" "bffa9739ce0752a37d9b1eee78fc00ba159748f50dc328af4be661484848e476" "5c9bd73de767fa0d0ea71ee2f3ca6fe77261d931c3d4f7cca0734e2a3282f439" "75bc4eb26434bbb4544db3e81a12acfc84d822ed0fd0706a42fa646089891043" "70a7b9c66c4b9063f5e735dbb5792e05eb60e2e02d51beb44c9c72cdeb97e4d1" default)))
 '(custom-unlispify-menu-entries nil)
 '(notmuch-saved-searches
   (quote
    ((:name "inbox" :query "tag:inbox" :key "i")
     (:name "unread" :query "tag:unread" :key "u")
     (:name "flagged" :query "tag:flagged" :key "f")
     (:name "sent" :query "tag:sent" :key "t")
     (:name "drafts" :query "tag:draft" :key "r")
     (:name "all mail" :query "*" :key "a")
     (:name "work" :query "tag:work" :key "w")
     (:name "school" :query "tag:school" :key "s")
     (:name "FreeBSD" :query "tag:bsd" :key "b")
     (:name "deleted" :query "tag:deleted" :key "d"))))
 '(send-mail-function (quote mailclient-send-it)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(global-set-key [(f1)] (lambda () (interactive) (manual-entry (current-word))))
