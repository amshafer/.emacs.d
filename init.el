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

(add-to-list 'load-path "~/.emacs.d/color-theme-6.6.0/")
(require 'color-theme)
(color-theme-initialize)

;; change theme on demand
(defun set-theme-mid ()
  (interactive)
  (color-theme-renegade))

(defun set-theme-dark ()
  (interactive)
  (color-theme-late-night))

(defun set-theme-light ()
  (interactive)
  (disable-theme custom-enabled-themes)
  (color-theme-black-on-gray))


(set-theme-mid)

;switch themes
(global-set-key (kbd "M-0") 'set-theme-dark)
(global-set-key (kbd "M-9") 'set-theme-mid)
(global-set-key (kbd "M-8") 'set-theme-light)