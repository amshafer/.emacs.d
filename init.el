;;; -*-emacs-lisp-*-
;;;

;;; to get colors to work, color-theme-* directory package should be 
;;; in ~/.emacs.d   - so should xcscope

; commonly used stuff
(global-set-key (kbd "C-u") 'undo-only)
(global-set-key (kbd "M-1") 'executable-interpret)
(global-set-key (kbd "M-3") 'replace-string)
(global-set-key (kbd "M-2") 'eval-buffer)

; multi buffer comfort
(global-set-key (kbd "M-n") 'next-buffer)
(global-set-key (kbd "M-p") 'previous-buffer)
(global-set-key (kbd "C-o") 'other-window)
(global-set-key (kbd "M-e") 'end-of-buffer)
(global-set-key (kbd "M-a") 'beginning-of-buffer)

(global-set-key (kbd "M-f") 'forward-page)
(global-set-key (kbd "M-b") 'backward-page)

;; cscope support
;(add-to-list 'load-path "~/.emacs.d/")
;(require 'xcscope)
;(cscope-setup)

;; cscope keybindings
;(global-set-key (kbd "C-c C-f") 'cscope-find-called-functions)
;(global-set-key (kbd "C-c i") 'cscope-find-files-including-file)
;(global-set-key (kbd "C-c c") 'cscope-find-functions-calling-this-function)
;(global-set-key (kbd "C-c g") 'cscope-find-global-definition)
;(global-set-key (kbd "C-c f") 'cscope-find-this-file)
;(global-set-key (kbd "C-c t") 'cscope-find-this-text-string)

;(global-set-key (kbd "C-c s") 'cscope-find-this-symbol)


;;;; notmuch for email
(add-to-list 'load-path "/usr/local/share/emacs/site-lisp/")
(autoload 'notmuch "notmuch" "notmuch mail" t)
(require 'notmuch)

(require 'notmuch) ; loads notmuch package
(setq message-kill-buffer-on-exit t) ; kill buffer after sending mail)
(setq mail-specify-envelope-from t) ; Settings to work with msmtp
;(setq message-sendmail-envelope-from header)
;(setq mail-envelope-from )
;(setq notmuch-fcc-dirs "G/[Gmail]Sent Mail") ; stores sent mail to the specified directory
;(setq message-directory "G/[Gmail]Drafts") ; stores postponed messages to the specified directory

;;;; set email sender

;; This is needed to allow msmtp to do its magic:
(setq message-sendmail-f-is-evil 't)

;;need to tell msmtp which account we're using
(setq message-sendmail-extra-arguments '("--read-envelope-from"))
;; with Emacs 23.1, you have to set this explicitly (in MS Windows)
;; otherwise it tries to send through OS associated mail client
(setq message-send-mail-function 'message-send-mail-with-sendmail)
;; we substitute sendmail with msmtp
(setq sendmail-program "/usr/local/bin/msmtp")
;;need to tell msmtp which account we're using
(setq message-sendmail-extra-arguments '("-a" "ashaferian"))
;; you might want to set the following too
(setq mail-host-address "gmail.com")
(setq user-full-name "Austin Shafer")
(setq user-mail-address "ashaferian@gmail.com")


;;;; colors and themes
(add-to-list 'load-path "~/.emacs.d/color-theme-6.6.0/")
(require 'color-theme)
(color-theme-initialize)

;; change theme on demand
(defun set-theme-mid ()
  (interactive)
  (disable-theme custom-enabled-themes)
  (color-theme-renegade))

(defun set-theme-dark ()
  (interactive)
  (disable-theme custom-enabled-themes)
  (color-theme-late-night))

(defun set-theme-light ()
  (interactive)
  (disable-theme custom-enabled-themes)
  (color-theme-black-on-gray))

(defun set-theme-silk ()
  (interactive)
  (disable-theme custom-enabled-themes)
  (color-theme-xp)
  (load-theme 'silkworm))


(set-theme-dark)

;switch themes
(global-set-key (kbd "M-0") 'set-theme-dark)
(global-set-key (kbd "M-9") 'set-theme-mid)
(global-set-key (kbd "M-8") 'set-theme-light)
(global-set-key (kbd "M-7") 'set-theme-silk)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   (quote
    ("70a7b9c66c4b9063f5e735dbb5792e05eb60e2e02d51beb44c9c72cdeb97e4d1" default)))
 '(send-mail-function (quote mailclient-send-it)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

(global-set-key [(f1)] (lambda () (interactive) (manual-entry (current-word))))
