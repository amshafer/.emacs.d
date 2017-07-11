;;; package.el --- Simple package system for Emacs  -*- lexical-binding:t -*-

;; Copyright (C) 2007-2017 Free Software Foundation, Inc.

;; Author: Tom Tromey <tromey@redhat.com>
;;         Daniel Hackney <dan@haxney.org>
;; Created: 10 Mar 2007
;; Version: 1.1.0
;; Keywords: tools
;; Package-Requires: ((tabulated-list "1.0"))

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; The idea behind package.el is to be able to download packages and
;; install them.  Packages are versioned and have versioned
;; dependencies.  Furthermore, this supports built-in packages which
;; may or may not be newer than user-specified packages.  This makes
;; it possible to upgrade Emacs and automatically disable packages
;; which have moved from external to core.  (Note though that we don't
;; currently register any of these, so this feature does not actually
;; work.)

;; A package is described by its name and version.  The distribution
;; format is either  a tar file or a single .el file.

;; A tar file should be named "NAME-VERSION.tar".  The tar file must
;; unpack into a directory named after the package and version:
;; "NAME-VERSION".  It must contain a file named "PACKAGE-pkg.el"
;; which consists of a call to define-package.  It may also contain a
;; "dir" file and the info files it references.

;; A .el file is named "NAME-VERSION.el" in the remote archive, but is
;; installed as simply "NAME.el" in a directory named "NAME-VERSION".

;; The downloader downloads all dependent packages.  By default,
;; packages come from the official GNU sources, but others may be
;; added by customizing the `package-archives' alist.  Packages get
;; byte-compiled at install time.

;; At activation time we will set up the load-path and the info path,
;; and we will load the package's autoloads.  If a package's
;; dependencies are not available, we will not activate that package.

;; Conceptually a package has multiple state transitions:
;;
;; * Download.  Fetching the package from ELPA.
;; * Install.  Untar the package, or write the .el file, into
;;   ~/.emacs.d/elpa/ directory.
;; * Autoload generation.
;; * Byte compile.  Currently this phase is done during install,
;;   but we may change this.
;; * Activate.  Evaluate the autoloads for the package to make it
;;   available to the user.
;; * Load.  Actually load the package and run some code from it.

;; Other external functions you may want to use:
;;
;; M-x list-packages
;;    Enters a mode similar to buffer-menu which lets you manage
;;    packages.  You can choose packages for install (mark with "i",
;;    then "x" to execute) or deletion (not implemented yet), and you
;;    can see what packages are available.  This will automatically
;;    fetch the latest list of packages from ELPA.
;;
;; M-x package-install-from-buffer
;;    Install a package consisting of a single .el file that appears
;;    in the current buffer.  This only works for packages which
;;    define a Version header properly; package.el also supports the
;;    extension headers Package-Version (in case Version is an RCS id
;;    or similar), and Package-Requires (if the package requires other
;;    packages).
;;
;; M-x package-install-file
;;    Install a package from the indicated file.  The package can be
;;    either a tar file or a .el file.  A tar file must contain an
;;    appropriately-named "-pkg.el" file; a .el file must be properly
;;    formatted as with package-install-from-buffer.

;;; Thanks:
;;; (sorted by sort-lines):

;; Jim Blandy <jimb@red-bean.com>
;; Karl Fogel <kfogel@red-bean.com>
;; Kevin Ryde <user42@zip.com.au>
;; Lawrence Mitchell
;; Michael Olson <mwolson@member.fsf.org>
;; Sebastian Tennant <sebyte@smolny.plus.com>
;; Stefan Monnier <monnier@iro.umontreal.ca>
;; Vinicius Jose Latorre <viniciusjl@ig.com.br>
;; Phil Hagelberg <phil@hagelb.org>

;;; ToDo:

;; - putting info dirs at the start of the info path means
;;   users see a weird ordering of categories.  OTOH we want to
;;   override later entries.  maybe emacs needs to enforce
;;   the standard layout?
;; - put bytecode in a separate directory tree
;; - perhaps give users a way to recompile their bytecode
;;   or do it automatically when emacs changes
;; - give users a way to know whether a package is installed ok
;; - give users a way to view a package's documentation when it
;;   only appears in the .el
;; - use/extend checkdoc so people can tell if their package will work
;; - "installed" instead of a blank in the    ((= num -2) "beta")
                      ((= num -3) "alpha")
                      ((= num -4) "snapshot"))
                str-list))))
      (if (equal "." (car str-list))
          (pop str-list))
      (apply 'concat (nreverse str-list)))))

(defun package-desc-full-name (pkg-desc)
  (format "%s-%s"
          (package-desc-name pkg-desc)
          (package-version-join (package-desc-version pkg-desc))))

(defun package-desc-suffix (pkg-desc)
  (pcase (package-desc-kind pkg-desc)
    (`single ".el")
    (`tar ".tar")
    (`dir "")
    (kind (error "Unknown package kind: %s" kind))))

(defun package-desc--keywords (pkg-desc)
  (let ((keywords (cdr (assoc :keywords (package-desc-extras pkg-desc)))))
    (if (eq (car-safe keywords) 'quote)
        (nth 1 keywords)
      keywords)))

(defun package-desc-priority (p)
  "Return the priority of the archive of package-desc object P."
  (package-archive-priority (package-desc-archive p)))

;; Package descriptor format used in finder-inf.el and package--builtins.
(cl-defstruct (package--bi-desc
               (:constructor package-make-builtin (version summary))
               (:type vector))
  version
  reqs
  summary)


;;; Installed packages
;; The following variables store information about packages present in
;; the system.  The most important of these is `package-alist'.  The
;; command `package-initialize' is also closely related to this
;; section, but it is left for a later section because it also affects
;; other stuff.
(defvar package--builtins nil
  "Alist of built-in packages.
The actual value is initialized by loading the library
`finder-inf'; this is not done until it is needed, e.g. by the
function `package-built-in-p'.
Each element has the form (PKG . PACKAGE-BI-DESC), where PKG is a package
name (a symbol) and DESC is a `package--bi-desc' structure.")
(put 'package--builtins 'risky-local-variable t)

(defvar package-alist nil
  "Alist of all packages available for activation.
Each element has the form (PKG . DESCS), where PKG is a package
name (a symbol) and DESCS is a non-empty list of `package-desc' structure,
sorted by decreasing versions.
This variable is set automatically by `package-load-descriptor',
called via `package-initialize'.  To change which packages are
loaded and/or activated, customize `package-load-list'.")
(put 'package-alist 'risky-local-variable t)

(defvar package-activated-list nil
  ;; FIXME: This should implicitly include all builtin packages.
  "List of the names of currently activated packages.")
(put 'package-activated-list 'risky-local-variable t)

;;;; Populating `package-alist'.
;; The following functions are called on each installed package by
;; `package-load-all-descriptors', which ultimately populates the
;; `package-alist' variabl (assq name package-alist)))
      (if (null old-pkgs)
          ;; If there's no old package, just add this to `package-alist'.
          (push (list name new-pkg-desc) package-alist)
        ;; If there is, insert the new package at the right place in the list.
        (while
            (if (and (cdr old-pkgs)
                     (version-list-< version
                                     (package-desc-version (cadr old-pkgs))))
                (setq old-pkgs (cdr old-pkgs))
              (push new-pkg-desc (cdr old-pkgs))
              nil)))
      new-pkg-desc)))

(defun package-load-descriptor (pkg-dir)
  "Load the description file in directory PKG-DIR."
  (let ((pkg-file (expand-file-name (package--description-file pkg-dir)
                                    pkg-dir))
        (signed-file (concat pkg-dir ".signed")))
    (when (file-exists-p pkg-file)
      (with-temp-buffer
        (insert-file-contents pkg-file)
        (goto-char (point-min))
        (let ((pkg-desc (or (package-process-define-package
                             (read (current-buffer)))
                            (error "Can't find define-package in %s" pkg-file))))
          (setf (package-desc-dir pkg-desc) pkg-dir)
          (if (file-exists-p signed-file)
              (setf (package-desc-signed pkg-desc) t))
          pkg-desc)))))

(defun package-load-all-descriptors ()
  "Load descriptors for installed Emacs Lisp packages.
This looks for package subdirectories in `package-user-dir' and
`package-directory-list'.  The variable `package-load-list'
c     (package-load-descriptor pkg-dir))))))))

(defun define-package (_name-string _version-string
                                    &optional _docstring _requirements
                                    &rest _extra-properties)
  "Define a neisabled.
Return the max version (as a string) if the package is held at a lower version."
  (let ((force (assq pkg-name package-load-list)))
    (cond ((null force) (not (memq 'all package-load-list)))
          ((null (setq force (cadr force))) t) ; disabled
          ((eq force t) nil)
          ((stringp force)              ; held
           (unless (version-list-= version (version-to-list force))
             force))
          (t (error "Invalid element in `package-load-list'")))))

(defun package-built-in-p (package &optional min-version)
  "Return non-nil if PACKAGE is built-in to Emacs.
Optional arg MIN-VERSION, if non-nt) ; For `package--builtins'.
        (assq package package--builtins))))))

(defun package--autoloads-file-name (pkg-desc)
  "Return the absolute name of the autoloads file, sans extension.
PKG-DESC is a `package-desc' object."
  (expand-file-name
   (format "%s-autoloads" (package-desc-name pkg-desc))
   (package-desc-dir pkg-desc)))

(defun package--activate-autoloads-and-load-path (pkg-desc)
  "Load the autoloads file and add package dir to `load-path'.
PKG-DESC is a `package-desc' object."
  (let* ((old-lp load-path)
         (pkg-dir (package-desc-dir pkg-desc))
         (pkg-dir-dir (file-name-as-directory pkg-dir)))
    (with-demoted-errors "Error loading autoloads: %s"
      (load (package--autoloads-file-name pkg-desc) nil t))
    (when (and (eq old-lp load-path)
               (not (or (member pkg-dir load-path)h))))

(defvar Info-directory-list)
(declare-function info-initialize "info" ())

(defun package--load-fies-for-activation: %s"
      (mapc (lambda (feature) (load feature nil t))
            ;; Skip autoloads file since we already evaluated it above.
            (remove (file-truename (package--autoloads-file-name pkg-desc))
                    loaded-files-list)))))

(defun package-activate-1 (pkg-desc &optional reload deps)
  "Activate package given by PKG-DESC, even if it was already active.
If DEPS is non-nil, also activate its dependencies (unless they
are already activated).
If RELOAD is non-nil, also `load' any files inside the package which
correspond to previously loaded files (those returned by
`package--list-loaded-files')."
  (let* ((name (package-desc-name pkg-desc))
         (pkg-dir (package-desc-dir pkg-desc)))
    (unless pkg-dir
      (error "Internal error: unable to find directory for `%s'"
             (package-desc-full-name pkg-desc)))
    ;; Activate 
      (dolist (req (package-desc-reqs pkg-desc))
        (unless (package-activate (car req))
          (error "Unable to activate package `%s'.\nRequired package `%s-%s' is unavailable"
                 name (car req) (package-version-join (cadr req))))))
    (package--load-files-for-activation pkg-desc reload)
    ;; Add info node.
    (when (file-exists-p (expand-file-name "dir" pkg-dir))
      ;; FIXME: not the friendliest, but simple.
      (require 'info)
      (info-initialize)
      (push pkg-dir Info-directory-list))
    (push name package-activated-list)
                             (and f (file-name-sans-extension f))))
                                load-history)))
         (dir (file-truename dir))
         ;; List all files that have already been loaded.
         (list-of-conflicts
          (delq
           nil
           (mapcar
               (lambda (x) (let* ((file (a list of features.  Files in
    ;; subdirectories are returned relative to DIR (so not actually features).
    (let ((default-directory (file-name-as-directory dir)))
      (mapcar (lambda (x) (file-truename (car x)))
        (sort list-of-conflicts
              ;; Sort the files by ascending HISTORY-POSITION.
              (lambda (x y) (< (cdr x) (cdr y))))))))

;;;; `package-activate'
;; This function activates a newer version of aisabled-p package available-version)
                ;; Prefer a builtin package.
                (package-built-in-p package available-version))))
      (setq pkg-descs (cdr pkg-descs)))
    (cond
     ;; If no such package is found, maybe it's built-in.
     ((null pkg-descs)
      (package-built-in-p package))
     ;; If the package is already activated, just return t.
     ((and (memq package package-activated-list) (not force))
      t)
     ;; Otherwise, proceed with activation.
     (t (package-activate-1 (car pkg-descs) nil 'fun package-untar-buffer (dir)
  "Untar the current buffer.
This uses `tar-untar-buffer' from Tar mode.  All files should
untar into a directory named DIR; otherwise, signal an error."
  (require 'tar-mode)
  (tar-mode)
  ;; Make sure everything extracts into DIR.
  (let ((regexp (concat "\\`" (regexp-quote (expand-file-name dir)) "/"))
        (case-fold-search (file-name-case-insensitive-p dir)))
    (dolist (tar-data tar-parse-info)
      (let ((name (expanr pair))) alist))))
(defun package-unpack (pkg-desc)
  "Install the contents of the current buffer as a package."
  (let* ((name (package-desc-name pkg-desc))
         (dirname (package-desc-full-name pkg-desc))
         (pkg-dir (expand-file-name dirname package-user-dir)))
    (pcase (package-desc-kind pkg-desc)
      (`dir
       (make-directory pkg-dir t)
       (let ((file-list
              (directory-files
               default-directory 'full "\\-directory package-user-dir t)
       ;; FIXME: should we delete PKG-DIR if it exists?
       (let* ((default-directory (file-name-as-directory package-user-dir)))
         (package-untar-buffer dirname)))
      (`single
       (let ((el-file (expand-file-name (format "%s.el" name) pkg-dir)))
         (make-directory pkg-dir t)
         (package--write-file-no-coding el-file)))
      (kind (error "Unknown package kind: %S" kind)))
    (package--make-autoloads-and-stuff pkg-desc pkg-dir)
    ;; Update package-alist.
    (let ((new-desc (package-load-descriptor pkg-dir)))
      (unless (equalcompiling.
      (package-activate-1 new-desc :reload :deps)
      ;; FIXME: Compilation should be done as a separate, optional, step.
      ;; E.g. for multi-package installs, we should first install all packages
      ;; and then compile them.
      (package--compile new-desc)
      ;; After compilation, load again any files loaded by
      ;; `activate-1', so that we use the byte-compiled deary pkg-desc)
                (let ((requires (package-desc-reqs pkg-desc)))
                  (list 'quote
                        ;; Turn version lists into string form.
                        (mapcar
                         (lambda (elt)
                           (list (car elt)
                                 (package-version-join (cadr elt))))
                         requires))))let* ((auto-name (format "%s-autoloads.el" name))
         ;;(ignore-name (concat name "-pkg.el"))
         (generated-autoload-file (expand-file-name auto-name pkg-dir))
         ;; We don't need 'em, and this makes the output reproducible.
         (autoload-timestamps nil)
         ;; Silence `autoload-generate-file-autoloads'.
         (noninteractive inhibit-message)
         (backup-inhibited t)
         (version-control 'never))
    (package-autoload-ensure-default-file generated-autoload-file)
    (update-directory-autoloads pkg-dir)
    (let ((buf (find-buffer-visiting generated-autoload-file)))
      (when buf (kill-buffer buf)))
    auto-name))

(defun package--make-autoloads-and-stuff (pkg-desc pkg-dir)
  "Generate autoloads, description file, etc.. for PKG-DESC instaldesc-file)
      (package-generate-description-file pkg-desc desc-file)))
  ;; FIXME: Create foo.info and dir file from foo.texi?
  )

;;;; Compilation
(defvar warning-minimum-level)
(defun package--compile (pkg-desc)
  "Byte-compile installed package PKG-DESC.
This assumes that `pkg-desc' has already been activated with
`package-activate-1'."
  (let ((warning-minimum-level :error)
        (save-silently inhibit-message)
        (load-path load-path))
    (byte-recompile-directory (package-desc-dir pkg-desc) 0 t)))

;;;  (if more-left
        (error "Can't read whole string")
      (car read-data))))

(defun package--prepare-dependencies (deps)
  "Turn DEPSer-info ()
  "Return a `package-desc' describing the package in the current buffer.
If the buffer does not contain a conforming package, signal an
error.  If there is a package, narrow the buffer to the file's
boundaries."
  (goto-char (point-min))
  (unless (re-search-forward "^;;; \\([^ ]*\\)\\.el ---[ \t]*\\(.*?\\)[ \t]*\\(-\\*-.*-\\*-[ \t]*\\)?$" nil t)
    (error "Package lacks a file header"))
  (let ((file-name (match-string-no-properties 1))
        (desc      (match-string-no-properties 2))
        (start     (line-beginning-position)))
    (unless (search-forward (concat ";;; " file-name ".el ends here"))
      (error "Package lacks a terminating comment"))
    ;; Try to include a trailing newline.
    (forward-line)
 it.  Otherwise try Version.
           (pkg-version
            (or (package-strip-rcs-id (lm-header "package-version"))
                (package-strip-rcs-id (lm-header "version"))))
           (homepage (lm-homepage)))
      (unless pkg-version
        (error
            "Package lacks a \"Version\" or \"Package-Version\" header"))
      (package-desc-from-define
       file-name pkg-version desc
       (if requires-str
           (package--prepare-dependencies
            (package-read-from-string requires-str)))
       :kind 'single
       :url homepage
       :maintainer (lm-maintainer)
       :authors (lm-authors)))))

(defun package--read-pkg-desc (kind)
  "Readppend (cdr pkg-def-parsed))))))
        (when pkg-desc
          (setf (package-desc-kind pkg-desc) kind)
          pkg-desc))))

(declare-function tar-get-file-descriptor "tar-mode" (file))
(declare-function tar--extract "tar-mode" (descriptor))

(defun package-tar-filefor a directory.
The return result is a `package-desc'."
  (cl-assert (derived-mode-p 'dired-mode))
  (let* ((desc-file (package--description-file default-directory)))
    (if (file-readable-p desc-file)
        (with-temp-buffer
          (insert-file-contents desc-file)
          (package--read-pkg-desc 'dir))
      (let ((files (directory-files default-directory t "\\.el\\'" t))
            info)
        (while files
          (with-temp-buffer
            (insert-file-contents (pop files))
            ;; When we find the file with the data,
            (when (setq info (ignore-errors (package-buffer-info)))
              ;; s; signature checking.
(defun package--write-file-no-coding (file-name)
  (let ((buffer-file-coding-system 'no-conversion))
    (write-region (point-min) (point-max) file-name nil 'silent)))

(declare-function url-http-file-exists-p "url-http" (url))

(defun package--archive-file-exists-p (location file)
  (let ((http (string-match "\\`https?:" location)))
    (if http
        (progn
          (require 'url-http)
          (url-http-file-exists-p (concat location file)))
      (file-exists-p (expand-file-name file location)))))

(declare-function epg-make-context "epg"
                  (&optional protocol armor textmode include-certs
                             cipher-algoripg" (signature) t)
(declare-function epg-signature-to-string "epg" (signature))

(defun package--display-verify-error (context sig-file)
  (unless (equal (epg-context-error-output context) "")
    (with-output-to-temp-buffer "*Error*"
      (with-current-buffer standard-output
        (if (epg-context-result-for cve to that base location.
This macro retrieves FILE from LOCATION into a temporary buffer,
and evaluates BODY while that buffer is current.  This work
buffer is killed afterwards.  Return the last value in BODY."
  (declare (indent 2) (debug t)
           (obsolete package--with-response-buffer "25.1"))
  `(with-temp-buffer
     (if (string-match-p "\\`https?:" ,location)
         (url-insert-file-contents (concat ,location ,file))
       (unless (file-name-absolute-p ,location)
         (error "Archive location %s is not an absolute file name"
           ,ORM is run only if a connection error occurs.  If NOERROR
is non-nil, don't propagate connection errors (does not apply to
errors signaled by ERROR-FORM or by BODY).
\(fn URL &key ASYNC FILE ERROR-FORM NOERROR &rest BODY)"
  (declare (indent defun) (debug t))
  (while (keywordp (car body))
    (setq body (cdr (cdr body))))
  (macroexp-let2* nil ((url-1 url)
                       (noerror-1 noerror))
    (let ((url-sym (make-symbol "url"))
          (b-sym (make-symbol "b-sym")))
      `(cl-macrolet ((unless-error (body-2 &rest      `(signal (car ,err) (cdr ,err)))))
                                          ,@body-2)))))
         (if (string-match-p "\\`https?:" ,url-1)
             (let ((,url-sym (concat ,url-1 ,file)))
               (if ,async
                   (unless-error nil
                                 (url-retrieve ,url-sym
                                               (lambda (status)
                                                 (let ((,b-sym (current-buffer)))
                                                   (require 'url-handl                                                           (unless (search-forward-regexp "^\r?\n\r?" nil 'noerror)
                                                                     (error "Error retrieving: %s %S" ,url-sym "incomprehensible buffer")))
                                                                 (url-insert-buffer-contents ,b-sym ,url-se-contents url))))))))

(define-error 'bad-signature "Failed to verify signature")

(defun package--check-signature-content (content string &optional sig-file)
  "Check signature CONTENT against STRING.
SIG-FILE is the name of the signature file, used when signaling
errors."
  (let ((context (epg-make-context 'OpenPGP)))
 signature because of
          ;; missing public key.  Other errors are still treated as
          ;; fatal (bug#17625).
          (unless (and (eq package-check-signature 'allow-unsigned)
                       (eq (epg-signature-status sig) 'no-pubkey))
            (setq had-fatal-error t))))
      (when (or (null good-signatures) had-fatal-error)
        (package--display-verify-error context sig-file)
        (signal 'bad-signature (list sig-file)))
      good-signatures)))

(defun package--check-signature (location file &optional string async callback unwind)
  "Check signature of the current buffer.
Download the signature file from LOCATION by appendin list of good signatures as argument (the list
can be empty).
If no signatures file is found, and `package-check-signature' is
`allow-unsigned', call CALLBACK with a nil argument.
Otherwise, an error is signaled.
UNWIND, if provided, is a function to be called after everything
else, even if an error ct
          (let ((sig (package--check-signature-content (buffer-substring (point) (point-max))
                                                       string sig-file)))
            (when callback (funcall callback sig))
            sig)
        (when unwind (funcall unwind))))))

;;; Packages on Archives
;; The following variables store information about packages available
;; from archives.  The most important of these is
;; `package-archive-contents' which is initially populated by the
;; function `package-read-all-archive-contents' from a cache on disk.
;; The `package-initialize' command is also closely related to thismapping package names (symbols) to
non-empty lists of `package-desc' structures.")
(put 'package-archive-contents 'risky-local-variable t)

(defvar package--compatibility-table nil
  "Hash table connecting package names to their compatibility.
Each key is a symbol, the name of a package.
The value is either nil, representing an incompatible package, or
a version list, representing the highest compatible version of
that package which is available.
A package is considered incompatible if it requires an Emacs
version higher than the one being used.  To check for package
\(in)compatibility, don't read this table directly, use
`package--incompatible-p' which also checks dependencies.")

(defun package--build-compatibility-table ()
  "Build `package--compatibility-table' with `package--mapc'."
  ;; Initialize the list of built-ins.
  (require 'finder-inf nil t)
  ;; Build compat table.
  (setq package--compatibility-table (make-hash-table :test 'eq))
  (package--mapc #'package--add-to-compatibility-table))

(defun package--add-to-compatibility-table (pkg)
  "If PKG is compatible (without dependencies), add to the compatibility table.
PKG is a package-desc object.
Only adds if its version is higher than what's already stored in
the table."
  (unless (package--incompatible-p pkg 'shallow)
    (let*c alist)
  "Append an entry for PKG-DESC to the start of ALIST and return it.
This entry takes the form (`package-desc-name' PKG-DESC).
If ALIST already has an entry with this name, destructively add
PKG-DESC to the cdr of this entry instead, sorted by version
number."
  (leary.
PACKAGE should have the form (NAME . PACKAGE--AC-DESC).
Also, add the originating archive to the `package-desc' structure."
  (let* ((name (car package))
         (version (package--ac-desc-version (cdr package)))
         (pkg-desc
          (package-desc-create
           :name name
           :version version
           :reqs (package--ac-desc-reqs (cdr package))
           :summary (package--ac-desc-summary (cdr package))
           :kind (package--ac-desc-kind (cdr package))
           :archive archive
           :extras (and (> (length (cdr package)) 4)
                        ;; Older archive-contents files have only 4
                        ;; elements here.
                        (package-ckage--append-to-alist pkg-desc package-archive-contents)))))

(defun package--read-archive-file (file)
  "Re-read archive file FILE, if it exists.
Will return the data from the file, or nil if the file does not exist.
Will throw an error if the archive version is too new."
  (let ((filename (expand-file-name file package-user-dir)))
    (when (file-exists-p filename)
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
         esentation.
  (let* ((contents-file (format "archives/%s/archive-contents" archive))
         (contents (package--read-archive-file contents-file)))
    (when contents
      (dolist (package contents)
        (package--add-to-archive-contents package archive)))))

(defvar package--old-archive-priorities nil
  "Store currently used `package-archive-prioritit lists of packages from contents
;; available on disk.
(defvar package--initialized nil)

(defvar package--init-file-ensured nil
  "Whether we know the init file has package-initialize.")

;;;###autoload
(defun package-initialize (&optional no-activate)
  "Load Emacs Lisp packages, and activate them.
The variable `package-load-list' controls which packages to load.
If optional arg NO-ACTIVATE is non-nil, don't activate packages.
If `user-init-file' does not mention `(package-initialize)', add
it to the file.
If called as part of loading `user-init-file', set
`package-enable-at-startup' to nil, to prevent accidentally
loading packages twice.
It is not necessary to adjust `loto ensure-init.
    (setq package--init-file-ensured t
          ;; And likely we don't need to run it again after init.
          package-enable-at-startup nil))
  (package-load-all-descriptors)
  (package-read-all-archive-contents)
  (unless no-activate
    (dolist (elt package-alist)
      (package-activate (car elt))))
  (setq package--initialized t)
  ;; This uses `package--mapc' so it must be called after
  ;; `package--initialized' is t.
  (package--build-compatibility-table))


;;;; Populating `package-archive-contents' from archives
;; This subsection populates the variables listed above from the
;; actual archives, instead of from a local cache.
(defvar package--downloads-in-progres
    (when package-gnupghome-dir
      (with-file-modes 448
        (make-directory package-gnupghome-dir t))
      (setf (epg-context-home-directory context) package-gnupghome-dir))
    (message "Importing %s..." (file-name-nondirectory file))
    (epg-import-keys-from-file context file)
    (message "Importing %s...done" (file-name-nondirectory file))))

(defvar package--post-download-archives-hook nil
  "Hook run after the archive contents are downloaded.
Don't run this hook directly.  It is meant to be run as part of
`package--update-downloads-in-progress'.")
(put 'package--post-download-archives-hook 'risky-local-variable t)

(defun package--update-downloads-in-progress (entry)
  "Remove ENTRY from `package--downloads-in-progress'.
Once it's empty, run `package--post-download-archives-hook'."
  ;; Keep track of the downloading progress.
  (setq package--downloads-in-progress
        (remove entry package--downloads-in-progress))
  ;; If this ds-in-progress
    (package-read-all-archive-contents)
    (package--build-compatibility-table)
    ;; We message before running the hook, so the hook can give
    ;; messages as well.
    (message "Package refresh done")
    (run-hooks 'package--post-download-archives-hook)))

(defun package--download-one-archive (archive file &optional async)
  "Retrieve an archive file FILE from ARCHIVE, and cache it.
ARCHIVE should be a cons cell of the form (NAME . LOCATION),
similar to an entry in `package-alist'.  Save the cached copy to
\"archives/NAME/FILE\" in `package-user-dir'."
  (package--with-response-buffer (cdr archive) :file file
    :async async
    :error-form (package--update-downloads-in-progress archive)
    (let* ((location (cdr archive))
           (name (car archive))
        ctory dir t)
        (if (or (not package-check-signature)
                (member name package-unsigned-archives))
            ;; If we don't care about the signature, save the file and
            ;; we're done.
            (progn (write-region content nil local-file nil 'silent)
                   (package--update-downloads-in-progress archive))
          ;; If we care, check it (perhaps async) and *then* write the file.
          (package--check-signature
           location file content async
           ;; This function will be called after signature checking.
           (lambda (&optional good-sigs)
             (write-region content nil local-file nil 'silent)
             ;; Write out goodun package--download-and-read-archives (&optional async)
  "Download descriptions of all `package-archives' and read them.
This populates `package-archive-contents'.  If ASYNC is non-nil,
perform the downloads asynchronously."
  ;; The downloaded archive contents will be read as part of
  ;; `package--update-downloads-in-progress'.
  (dolist (archive package-archives)
    (cl-pushnew archive package--downloads-in-progress
                :test #'equal))
  (dolist (archive package-archives)
    (condition-case-unless-debug nil
        (package--download-one-archive archive "archive-contents" async)
      (error (message "Failed to download `%s' archive."
               (car archive))))))

;;;###autoload
(defun package-refresh-contents (&optional async)
  "Download descripether to perform the
downloads in the background."
  (interactive)
  (unless (file-exists-p package-user-dir)
    (make-directory package-user-dir t))
  (let ((default-keyring (expand-file-name "package-keyring.gpg"
                                           data-directory))
        (inhibit-message async))
    (when (and package-check-signature (file-exists-p default-keyring))
      (condition-case-unless-debug error
          (package-import-keyring default-keyring)
`package-desc'.
REQUIREMENTS should be a list of additional requirements; each
element in this list should have the form (PACKAGE VERSION-LIST),
where PACKAGE is a package name and VERSION-LIST is the required
version of that package.
This function recursively computes the requirements of the
packages in REQUIREMENTS, and returns a list of all the packages
that must be installed.  Packages that are already installed are
not included in this list.
SEEN is used internally to detect infinite recursion."
  ;; FIXME: We really should use backtracking to explore the whole
  ;; search space (e.g. if foo require bar-1.3, and bar-1.4 requires toto-1.1
  ;; whereas bar-1.3 requires toto-1.0 and the user has put a hold on toto-1.0:
  ;; the current code might fail to see that it could install foo by using the
  ;; older bar-1.3).
  (dolist (elt requirements)
    (let* ((next-pkg (car elt))
           (next-version (cadr elt))
           (already ()))
      (dolist (pkg packages)
        (if (eq next-pkg (package-desc-name pkg))
            (setq already pkg)))
      (when already
        (if (version-list-<= next-version (package-desc-version already))
            ;; `next-pkg' is already in `packages', but its position there
            ;; means it might be installed too late: remove it from there, so
            ;; we re-add it (along with its dependencies) at an earlier place
            ;; below (bug#16994).
            (if (memq already seen)     ;Avoid inf-loop on dependency cycles.
                (message "Dependency cycle going through %S"
                         (package-desc-full-name already))
              (setq packages (delq already packages))
              (setq already nil))
          (error "Need package `%s-%s', but only %s is being installed"
                 next-pkg (package-version-join next-version)
                 (package-version-join (package-desc-version already)))))
      (cond
       (already nil)
       ((package-installed-p next-pkg next-version) nil)

       (t
        ;; A package is required, but not installed.  It might also be
        ;; blocked via `package-load-list'.
        (let ((pkg-descs (cdr (assq next-pkg package-archive-contents)))
              (found nil)
              (found-something nil)
              (problem nil))
          (while (and pkg-descs (not found))
            (let* ((pkg-desc (pop pkg-descs))
                   (version (package-desc-version pkg-desc))
                   (disabled (package-disabled-p next-pkg version)))
              (cond
               ((version-list-< version next-version)
                ;; pkg-descs is sorted by priority, not version, so
                ;; don't error just yet.
                (unless found-something
                  (setq found-something (package-version-join version))))
               (disabled
                (unless %s required"
                             next-pkg disabled
                             (package-version-join next-version))
                          (format-message "Required package `%s' is disabled"
                                          next-pkg)))))
               (t (setq found pkg-desc)))))
          (unless found
            (cond
             (problem (error "%s" problem))
             (found-something
              (error "Need package `%s-%s', but only %s is available"
                     next-pkg (package-version-join next-version)
                     found-something))
             (t (error "Pacst of installed packages which are not dependencies.
Finds all packages in `package-alist' which are not dependencies
of any other packages.
Used to populate `package-selected-packages'."
  (let ((dep-list
         (delete-dups
          (apply #'append
            (mapcar (lambda (p) (mapcar #'car (package-desc-reqs (cadr p))))
                    package-alist)))))
    (cl-loop for p in package-alist
             for name = (car p)
    ame.
This looks into `package-selected-packages', populating it first
if it is still empty."
  (unless (consp package-selected-packages)
    (package--save-selected-packages (package--find-non-dependencies)))
  (memq pkg package-selected-packages))

(defun package--get-deps (pkg &optional only)
  (let* ((pkg-desc (cadr (assq pkg package-alist)))
         (direct-deps (cl-loop for p in (package-desc-reqs pkg-desc)
                               for name = (car p)
                               when (assq name package-alist)
                               collect name))
         (indirect-deps (unless (eq only 'direct)
                          (delete-dups
                           (cl-loop for p in direct-deps
                                    append (package--get-deps p))))))
    (cl-case only
      (direct   direct-deps)
      (separate (list direct-deps indirect-deps))
      (indirect indirect-deps)
      (t        (delete-dups (append direct-deps indirect-deps))))))

(defun package--removable-packages ()
  "Return a list of names of packages no longer needed.
These are packages which are neither contained in
`package-selected-packages' nor a dependency of one that is."
  (let ((needed (cl-loop for p in package-selected-packages
                         if (assq p package-alist)
                         ;; `p' and its dependencies are needed.
                 (remove (assq pkg package-alist)
                              package-alist))))
      (if all
          (cl-loop for p in alist
                   if (assq pkg (package-desc-reqs (cadr p)))
                   collect (cadr p))
        (cl-loop for p in alist thereis
                 (and (assq pkg (package-desc-reqs (cadr p)))
                      (cadr p)))))))

(defun package--sort-deps-in-alist (package only)
  "Return a list of dependencies for PACKAGE sorted by dependency.
PACKAGE is included as the first element of the returned list.
ONLY is an alist associating package names to package objects.
Only these packages will be in the return value an their cdrs are
destructively set to nil in ONLY."
  (let ((out))
    (dolist (dep (package-desc-reqs package))
      (when-age out)))

(defun package--sort-by-dependence (package-list)
  "Return PACKAGE-LIST sorted by dependence.
That is, any element of the returned list is guaranteed to not
directly depend on any elements that come before it.
PACKAGE-LIST is a list of `package-desc' objects.
Indirect dependencies are guaranteed to be returned in order only
if all the in-between dependencies are also in PACKAGE-LIST."
  (let ((alist (mapcar (lambda (p) (cons (package-desc-name p) p)) package-list))
        out-list)
    (dolist (cell alist out-list)
      ;; `package--sort-deps-in-alist' destructively changes alist, so
      ;; some cells might already be empty.  We check this here.
      (when-let ((pkg-desc (cdr cell)))
        (setcdr cell nil)
        (setq out-list
              (append (package--sort-deps-in-ale actual
;; functions that install packages.  The package itself can be
;; installed in a variety of ways (archives, buffer, file), but
;; requirements (dependencies) are always satisfied by looking in
;; `package-archive-contents'.
(defun package-archive-base (desc)
  "Return the archive containing the package NAME."
  (cdr (assoc (package-desc-archiv ;; If we don't care about the signature, unpack and we're
          ;; done.
          (let ((save-silently t))
            (package-unpack pkg-desc))
        ;; If we care, check it and *then* write the file.
        (let ((content (buffer-string)))
          (package--check-signature
           location file content nil
           ;; This function will be called after signature checking.
           (lambda (&optional good-sigs)
             ;; Signature checked, unpack now.
             (with-temp-buffer (insert content)
                               (let ((save-silently t))
                                 (package-unpack pkg-desc)))
 name
                              (concat (package-desc-full-name pkg-desc) ".signed")
                              package-user-dir)
                             nil 'silent)
               ;; Update the old pkg-desc which will be shown on the description buffer.
               (setf (package-desc-signed pkg-desc) t)
               ;; Update the new (activated) pkg-desc as well.
               (when-let ((pkg-descs (cdr (assq (package-desc-name pkg-desc) package-alist))))
                 (setf (package-desc-signed (car pkg-descs)) t))))))))))

(defun package-installed-p      (file-exists-p dir)))
    (or
     (let ((pkg-descs (cdr (assq package package-alist))))
       (and pkg-descs
            (version-list-<= min-version
                             (package-desc-version (car pkg-descs)))))
     ;; Also check built-in packages.
     (package-built-in-p package min-version))))

(defuninit-file)
             (not package--init-file-ensured)
             (file-readable-p user-init-file)
             (file-writable-p user-init-file))
    (let* ((buffer (find-buffer-visiting user-init-file))
           buffer-name
           (contains-init
            (if buffer
                (with-current-buffer buffer
                  (save-excursion
                    (save-restriction
                      (widen)
                      (goto-char (point-min))
                      (re-search-forward "(package-initialize\\_>" nil 'noerror))))
              ;; Don't visit the file if we don't have to.
              (with-temp-buffer
                (insert-file-                            (find-file-noselect user-init-file)))
          (when buffer
            (setq buffer-name (buffer-file-name))
            (set-visited-file-name (file-chase-links user-init-file)))
          (save-excursion
            (save-restriction
              (widen)
              (goto-char (point-min))
              (while (and (looking-at-p "[[:blank:]]*\\(;\\|$\\)")
                          (not (eobp)))
                (forward-line 1))
              (insert
               "\n"
               ";; Added by P)
              (if buffer
                  (progn
                    (set-visited-file-name buffer-name)
                    (set-buffer-modified-p nil))
                (kill-buffer (current-buffer)))))))))
  (setq package--init-file-ensured t))

;;;###autoload
(defun package-install (pkg &optional dont-select)
  "Install the package PKG.
PKG can be a `package-desc' or a symbol naming one of the available packages
in an archive in `package-archives'.  Interactively, prompt for its name.
If called interactively or if DONT-SELECT nil, add PKG to
`package-selected-packages'.
Iage: "
                    (delq nil
                          (mapcar (lambda (elt)
                                    (unless (package-installed-p (car elt))
                                      (symbol-name (car elt))))
                                  package-archive-contents))
                    nil t))
           nil)))
  (add-hook 'post-command-hook #'package-menu--post-refresh)
  (let ((name (if (package-desc-p pkg)
                  (package-desc-name pkg)
                pkg)))
    (unless (or dont-select (package--user-selected-p name))
      (package--save-selected-packages
       (cons name package-selected-packages)))
    (if-let ((transaction
              (if (package-desc-p pkg)
                  (unless (package-installed-p pkg)
                    (package-compute-transaction (list pkg)
                                    message "`%s' is already installed" name))))

(defun package-strip-rcs-id (str)
  "Strip RCS version ID from the version string STR.
If the result looks like a dotted numeric version, return it.
Otherwise return nil."
  (when str
    (when (string-match "\\`[ \t]*[$]Revision:[ \t]+" str)
      (setq str (substring str (match-end 0))))
    (ignore-errors
      (if (version-to-list str) str))))

(declare-function lm-homepage "lisp-mnt" (&optional file))

;;;###autoload
(defun package-install-from-buffer ()
  "Install a package from the current buffer.
The current buffer is assumed to be a single .el or .tar file or
a directory.  These must follow the packaging guidered-mode)
             ;; This is the only way a package-desc object with a `dir'
             ;; desc-kind can be created.  Such packages can't be
             ;; uploaded or installed from archives, they can only be
             ;; installed from local buffers or directories.
             (package-dir-info))
            ((derived-mode-p 'tar-mode)
             (package-tar-file-info))
            (t
 file.
The file can either be a tar file, an Emacs Lisp file, or a
directory."
  (interactive "fPackage file name: ")
  (with-temp-buffer
    (if (file-directory-p file)
        (progn
          (setq default-directory file)
          (dired-mode))
      (insert-file-)) not-installed))
           (difference (- (length not-installed) (length available))))
      (cond
       (available
        (when (y-or-n-p
               (format "%s packages will be installed:\n%s, proceed?"
                       (length available)
                       (mapconcat #'symbol-name available ", ")))
          (mapc (lambda (p) (package-install p 'dont-select)) available)))
       ((> difference 0)
        (message "%s packages are not available (the rest already installed), maybe you need to `M-x package-refresh-contents'"
                 difference))
       (t
        (message "All your packages are already installed"))))))


;;; Package Deletier for the package name and version.
When package is used elsewhere as dependency of another package,
refuse deleting it and return an error.
If prefix argument FORCE is non-nil, package will be deleted even
if it is used elsewhere.
If NOSAVE is non-nil, the package is not removed from
`package-selected-packages'."
  (interactive
   (progn
     ;; Initialize the package system to get the list of package
     ;; symbols for completion.
     (unless package--initialized
       (package-initialize t))
     (let* ((package-table
             (mapcar
              (lambda (p) (cons (package-desc-full-name table))
             current-prefix-arg nil))))
  (let ((dir (package-desc-dir pkg-desc))
        (name (package-desc-name pkg-desc))
        pkg-used-elsewhere-by)
    ;; If the user is trying to delete this package, they definitely
    ;; don't want it marked as selected,    ((and (null force)
                (setq pkg-used-elsewhere-by
                      (package--used-elsewhere-p pkg-desc)))
           ;; Don't delete packages used as dependency elsewhere.
           (error "Package `%s' is used by `%s' as dependency, not deleting"
                  (package-desc-full-name pkg-desc)
                  (package-desc-name pkg-used-elsewhere-by)))
          (t
           (add-hook 'post-command-hook #'package-menu--post-refresh)
           (delete-directory dir t t)
           ;; Remove NAME-VERSION.signed and NAME-rea        ;; Update package-alist.
           (let ((pkgs (assq name package-alist)))
             (delete pkg-desc pkgs)
             (unless (cdr pkgs)
               (setq package-alist (delq pkgs package-alist))))
           (message "Package `%s' deleted." (package-desc-full-name pkg-desc))))))

;;;###autoload
(defun package-reinstall (pkg)
  "Reinstall package PKG.
PKG should be either a symbol, the package name, or a `package-desc'
object."
  (interactive (list (intern (completing-read
    )tyd  (interactive)
  ;; If `package-selected-packages' is nil, it would make no sense to
  ;; try to populate it here, because then `package-autoremove' will
  ;; do absolutely nothing.
  (when (or package-selected-packages
            (yes-or-no-p
             (format-message
              "`package-selected-packages' is empty! Really remove ALL packages? ")))
    (let ((removable (package--removable-packages)))
      (if removab           (symbol-at-point))))
     (require 'finder-inf nil t)
     ;; Load the package list if necessary (but don't activate them).
     (unless package--initialized
       (package-initialize t))
     (let ((packages (append (mapcar 'car package-alist)
                             (mapcar 'car package-archive-contents)
                             (mapcar 'car package--builtins))))
       (unless (memq guess paage specified")
    (help-setup-xref (list #'describe-package package)
                     (called-interactively-p 'interactive))
    (with-help-window (help-buffer)
      (with-current-buffer standard-output
        (describe-package-1 package)))))

(defface package-help-section-name
  '((t :inherit (bold font-lock-function-name-face)))
  "Face used on section names in package description buffers."
  :version "25.1")

(defun package--print-help-section (name &rest strings)
  "Print \"NAME: \", right aligned to the 13th column.
If more STRINGS are provided, insert them followed by a newline.
Otherwise no newline is inserted."
  (declare (indent 1))
  (insert (make-string (max 0 (- 11 (string-width nam(if (package-desc-p pkg) pkg)
                (cadr (assq pkg package-alist))
                (let ((built-in (assq pkg package--builtins)))
                  (if built-in
                      (package--from-builtin built-in)
                    (cadr (assq pkg package-archive-contents))))))
         (name (if desc (package-desc-name desc) pkg))
         (pkg-dir (if desc (package-desc-dir desc)))
         (reqs (if desc (package-desc-reqs desc)))
         (required-by (if desc (package--used-elsewhere-p desc nil 'all)))
         (version (if desc (package-         (signed (if desc (package-desc-signed desc))))
    (when (string= status "avail-obso")
      (setq status "available obsolete"))
    (when incompatible-reason
      (setq status "incompatible"))
    (prin1 name)
    (princ " is ")
    (princ (if (memq (aref status 0) '(?a ?e ?i ?o ?u)) "an " "a "))
    (princ status)
    (princ " package.\n\n")

    (package--print-help-section "Status")
    (cond (built-in
           (insert (propertize (capitalize status)
                               'firectory-p pkg-dir package-user-dir)
                            (file-relative-name pkg-dir package-user-dir)
                          pkg-dir)))))
             (help-insert-xref-button dir 'help-package-def pkg-dir))
           (if (and (package-built-in-p name)
                    (not (package-built-in-p name version)))
               (insert (substitute-command-keys
                        "',\n             shadowing a ")
                       (propertize "built-in package"
                                   'font-lock-face 'package-status-built-in))
             (insert (substitute-command-keys "'")))
           (if signed
               (insert ".")
             (insert " (unsigned)."))
           (when (and (package-desc-p desc)
                      (not required-by)
                      (member status '("unsigned" "installed")))
             (insert " ")
             (package-make-button "Delete"
                                  'action #'package-delete-button-action
                                  'package-desc desc)))
          (incompatible-reason
           (insert (propertize "Incompatible" 'font-lock-face font-lock-warning-face)
                   " because it depends on ")
           (if (stringp incompatible-reason)
               (insert "Emacs " incompatible-reason ".")
             (insert "uninstallable packages.")))
          (installable
           (insert (capitalize status))
           o-desc-summary desc)))

    (setq reqs (if desc (package-desc-reqs desc)))
    (when reqs
      (package--print-help-section "Requires")
      (let ((first t))
        (dolist (req reqs)
          (let* ((name (car req))
                 (vers (cadr req))
                 (text (format "%s-%s" (symbol-name name)
                               (package-version-join vers)))
                 (reason (if (and (listp incompatible-reason)
                                  (assq name incompatible-reason))
                             " (not available)" "")))
            (cond (first (setq first nil))
                  ((>= (+ 2 (current-column) (length text) (length reason))
                       (window-width))
                   (insert ",\n       list (pkg required-by)
          (let ((text (package-desc-full-name pkg)))
            (cond (first (setq first nil))
                  ((>= (+ 2 (current-column) (length text))
                       (window-width))
                   (insert ",\n               "))
                  (t (insert ", ")))
            (help-insert-xref-button text 'help-package
                                     (package-desc-name pkg))))
        (insert "\n")))
    (when      (dolist (k keywords)
        (package-make-button
         k
         'package-keyword k
         'action 'package-keyword-button-action)
        (insert " "))
      (insert "\n"))
    (let* ((all-pkgs (append (cdr (assq name package-alist))
                             (cdr (assq name package-archive-contents))
                                      (make-text-button (package-version-join ov) nil
                                                     'font-lock-face 'link
                                                     'follow-link t
                                                     'action
                                                     (lambda (_button)
                                                       (describe-package opkg)))
                                   from))))
                     oth        (replace-match ""))))
      (let* ((basename (format "%s-readme.txt" name))
             (readme (expand-file-name basename package-user-dir))
             readme-string)
        ;; For elpa packages, try downloading the commentary.  If that
        ;; fails, try an existing readme file in `package-user-dir'.
        (cond ((and (package-desc-archive desc)
                    (package--with-response-buffer (package-archive-base desc)
                 contents readme)
               (goto-char (point-max))))))))

(defun package-install-button-action (button)
  (let ((pkg-desc (button-get button 'package-desc)))
    (when (y-or-n-p (format-message "Install package `%s'? "
                                    (package-desc-full-name pkg-desc)))
      (package-install pkg-desc nil)
      (revert-buffer nil t)
      (goto-char (point-min)))))

(defun package-delete-button-action (button)
  (let ((pkg-desc (button-get button 'package-desc)))
    (when (y-or-n-p (format-message "Delete package `%s'? "
                                    (package-desc-full-name if (display-graphic-p)
                         '(:box (:line-width 2 :color "dark grey")
                                :background "light grey"
                                :foreground "black")
                       'link)))
    (apply 'insert-text-button button-text 'face button-face 'follow-link t
           props)))


;;;; Package menu mode.

(defvar package-menu-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map "\C-m" 'package-menu-describe-package)
    (define-key map "u" 'package-menu-mark-unmark)
" 'package-menu-quick-help)
    (define-key map "H" #'package-menu-hide-package)
    (define-key map "?" 'package-menu-describe-package)
    (define-key map "(" #'package-menu-toggle-hiding)
    map)
  "Local keymap for `package-menu-mode' buffers.")

(easy-menu-define package-menu-mode-menu package-menu-mode-map
  "Menu for `package-menu-mode'."
  `("Package"
    ["Describe Package" package-menu-describe-packupgrading"
     :active (not package--downloads-in-progress)]
    ["Mark All Obsolete for Deletion" package-menu-mark-obsolete-for-deletion :help "Mark all obsolete packages for deletion"]
    ["Mark for Install" package-menu-mark-install :help "Mark a package for installation and move to the next line"]
    ["Mark for Deletion" package-menu-mark-delete :help "Mark a package for deletion and move to the next line"]
    ["Unmark" package-menu-mark-unmark :help "Clear any marks on a package and move to the next line"]

    "--"
    oup 'package)]))

(defvar package-menu--new-package-list nil
  "List of newly-available packages since `list-packages' was last called.")

(defvar package-menu--transaction-status nil
  "Mode-line status of ongoing package transaction.")

(define-derived-mode package-menu-mode tabulated-list-mode "Package Menu"
  "Major mode for browsing a list of packages.
Letters do not insert themselves; instead, they are c tabulated-list-sort-key (cons "Status" nil))
  (add-hook 'tabulated-list-revert-hook 'package-menu--refresh nil t)
  (tabulated-list-init-header))

(defmacro package--push (pkg-desc status listname)
  "Convenience macro for `package-menu--generate'.
If the alist stored in the symbol LISTNAME lacks an entry for a
package PKG-DESC, add one.  The alist is keyed with PKG-DESC."
  `(unless (assoc ,pkg-desc ,listname)
     ;; FIXME: Should we move status into pkg-desc?
     (push (cons ,pkg-desc ,status) ,listname)))

(defvar package-list-unversioned nil
  "If this only checks if PKG depends on a
higher `emacs-version' than the one being used.  Otherwise, also
checks the viability of dependencies, according to
`package--compatibility-table'.
If PKG requires an incompatible Emacs version, the return value
is this version (as a string).
If PKG requires incompatible packages, the return value is a list
of these dependencies, similar to the list returned by
`package-desc-reqs'."
  (let* ((reqs    (package-desc-reqs pkg))
         (version (cadr (assq 'emacs reqs))))
    (if (and version (version-list-< packageus (pkg-desc)
  (let* ((name (package-desc-name pkg-desc))
         (dir (package-desc-dir pkg-desc))
         (lle (assq name package-load-list))
         (held (cadr lle))
         (version (package-desc-version pkg-desc))
         (signed (or (not package-list-unsigned)
                     (package-desc-signed pkg-desc))))
    (cond
     ((eq dir 'builtin) "built-in")
     ((and lle (null held)) "disabled")
     ((stringp held)
      (let ((hv (if (stringp held) (ver"installed" "dependency")))
       (t "obsolete")))
     ((package--incompatible-p pkg-desc) "incompat")
     (t
      (let* ((ins (cadr (assq name package-alist)))
             (ins-v (if ins (package-desc-version ins))))
        (cond
         ;; Installed obsolete packages are handled in the `dir'
         ;; clause above.  Here we handle available obsolete, which
         ;; are displayed depending on `package-menu--hide-packages'.
         ((and ins (version-list-<= version ins-v)) "avail-obso")
         (t
        buffer is not a Package Menu"))
  (setq package-menu--hide-packages
        (not package-menu--hide-packages))
  (message "%s packages" (if package-menu--hide-packages
                             "Hiding obsolete or unwanted"
                           "Displaying all"))
  (revert-buffer nil 'no-confirm))

(defun package--remove-hidden (pkg-list)
  "Filter PKG-LIST according to `package-archive-priorities'.
PKG-LIST must be a list of `package-desc' objects, all with the
same name, sorted by decreasing `package-desc-priority-version'.
Return a list of packages tied for the highest priority according
to their archives."
  (when pkg-list
    ;; Variable toggled with `package-menu-toggle-hiding'.
    (if (not package-menu--hide-packages)
        pkg-list
      (let ((installed (cadr (assq (package-desc-nal-remove-if (lambda (p) (version-list-< (package-desc-version p)
                                                       ins-version))
                                pkg-list))))
        (let ((filtered-by-priority
               (cond
                ((not package-menu-hide-low-priority)
                 pkg-list)
                ((eq package-menu-hide-low-priority 'archive)
                 (let* ((max-priority most-negative-fixnum)
                        (out))
                   (while pkg-list
                     (let ((p (pop pkg-list)))
                       (let ((priority (package-desc-priority p)))
                         (if (< priority max-priority)
                             (setq pkg-list nil)
                           (push p out)
                           (setq max-priority priority)))))
                   (nreverse out)))
                (pkg-list
                 (list (car pkg-list))))))
          (if (not installed)
              filtered-by-priority
            (let ((ins-version (package-desc-version installed)))
              (cl-remove-if (lambda (p) (version-list-= (package-desc-version p)
                                                   ins-version))
                            filtered-by-priority))))))))

(defcustom package-hidden-regexps nil
  "List of regexps matching the name of packages to hide.
If the name of a package matches any of these regexps it is
omitted from the package menu.  To toggle this, type \\[package-menu-toggle-hiding].
Values can be interactively added to this list by typing
\\[package-menu-hide-package] on a package"
  :version "25.1"
  :type '(repeat (regexp :tag "Hide packages with name matching")))

(defun package-menu--refresh (&optional packages keywords)
  "Re-populate the `tabulated-list-entries'.
PACKAGES should be nil or t, which means to display all known packages.
KEYWORDS should be nil or a list of keywords."
  ;; Construct list of (PKG-DESC . STATUS).
  (unless packages (setq packages t))
  (let-hidden-regexps "\\|"))
        info-list)
    ;; Installed packages:
    (dolist (elt package-alist)
      (let ((name (car elt)))
        (when (or (eq packages t) (memq name packages))
          (dolist (pkg (cdr elt))
            (when (package--has-keyword-p pkg keywords)
              (push pkg info-list))))))

    ;; Built-in packages:
    (dolist (elt package--builtins)
      (let ((pkg  (package--from-builtin elt))
            (name (car elt)))
        (when (not (eq name 'emacs)) ; Hide the `emacs' package.
          (when (and (package--has-keyword-p pkg keywords)
            elt)))
        ;; To be displayed it must be in PACKAGES;
        (when (and (or (eq packages t) (memq name packages))
                   ;; and we must either not be hiding anything,
                   (or (not package-menu--hide-packages)
                       (not package-hidden-regexps)
                       ;; or just not hiding this specific package.
                  list))))
    key-list))

(defun package--mapc (function &optional packages)
  "Call FUNCTION for all known PACKAGES.
PACKAGES can be nil or t, which means to display all known
packages, or a list of packages.
Built-in packages are converted with `package--from-builtin'."
  (unless packages (setq packages t))
  (let (name)
    ;; Installed packages:
    (dolist (elt package-alist)
      (setq name (car elt))
    ) (memq name packages))
        (dolist (pkg (cdr elt))
          ;; Hide obsolete packages.
          (unless (package-installed-p (package-desc-name pkg)
                                       (package-desc-version pkg))
        (funcall function pkg)))))))

(defun package--has-keyword-p (desc &optional keywords)
  "Test if package DESC has any of the given KEYWORDS.
When none are given, the package matches."
  (if keywords
      (let ((desc-keywords (and desc (package-desc--keywords desc)))
            found)
        (while (and (not found) keywords)
          (let ((k (pop keywords)))
            (setq found
                  (or (string= k (concat "arc:" (package-desc-archive desc)))
                      (string= k (concat "status:" (package-desc-status desc)))
                      (member k desc-keywords)))))
        found)
    t))

(defun package-menushould be t, which means to display all known packages,
or a list of package names (symbols) to display.
With KEYWORDS given, only packages with those keywords are
shown."
  (package-menu--refresh packages keywords)
  (setf (car (aref tabulated-list-format 0))
        (if keywords
            (let ((filters (mapconcat 'identity keywords ",")))
              (concat "Package[" filters "]"))
          "Package"))
  (if keywords
      (define-key package-menu-mode-map "q" 'package-show-package-list)
    (define-key package-menu- link))
  "Face used on package names in the package menu."
  :version "25.1")

(defface package-description
  '((t :inherit default))
  "Face used on package description summaries in the package menu."
  :version "25.1")

;; Shame this hypheneld packages."
  :version "25.1")

(defface package-status-disabled
  '((t :inherit font-lock-warning-face))
  "Face used on the status and version of disabled packages."
  :version "25.1")

(defface package-status-installed
  '((t :inherit font-lock-comment-face))
  "Face used on the status and version of installed fo-simple (pkg)
  "Return a package entry suitable for `tabulated-list-entries'.
PKG is a `package-desc' object.
Return (PKG-DESC [NAME VERSION STATUS DOC])."
  (let* ((status  (package-desc-status pkg))
         (face (pcase status
                 (`"built-in"  'package-status-built-in)
                 (`"external"  'package-status-external)
                 (`"available" 'package-status-available)
                 (`"avail-obso" 'package-status-avail-obso)
                 (`"new"       'package-status-new)
                 (`"held"      'package-status-held)
                 (`"disabled"  'package-status-disabled)
                 (`"installed" 'package-status-installed)
                 (`"dependency" 'package-status-dependency)
                 (`"unsigned"  'package-status-unsigned)
                 (`"incompat"  'package-status-incompatme
             font-lock-face package-name
             follow-link t
             package-desc ,pkg
             action package-menu-describe-package)
            ,(propertize (package-version-join
                          (package-desc-version pkg))
                         'font- current buffer is not a Package Menu"))
  (setq package-menu--old-archive-contents package-archive-contents)
  (setq package-menu--new-package-list nil)
  (package-refresh-contents package-menu-async))

(defun package-menu-hide-package ()
  "Hide a package under point.
If optional arg BUTTON is non-nil, descri                          package-archive-contents)))
      (message (substitute-command-keys
                (concat "Hiding %s packages, type `\\[package-menu-toggle-hiding]'"
                        " to toggle or `\\[customize-variable] RET package-hidden-regexps'"
                        " to customize it"))
        (length hidden)))))

(defun package-menu-describe-package (&optional button)
  "Describe the current package.
If optional arg BUTTON is non-nil, describe its associated package."
  (interactive)
  (let ((pkg-desc (if button (button-get button 'package-desc)
                    (tabulated-list-get-id))))
    (if pkg-desc
        (describe-package porward-line)))

(defun package-menu-mark-install (&optional _num)
  "Mark a package for installation and move to the next line."
  (interactive "p")
  (if (member (package-menu-get-status) '("available" "avail-obso" "new" "dependency"))
      (tabulated-list-put-text," "previous")
    ("Hide-package," "(-toggle-hidden")
    ("refresh-contents," "g-redisplay," "filter," "help")))

(defun package--prettify-quick-help-key (desc)
  "Prettify DESC to be displayed as a help menu."
  (if (listp desc)
      (if (listp (cdr desc))
          (mapconcat #'package--prettify-quick-help-key desc "   ")
        (let ((place (cdr desc))
              (out (car desc)))
          (add-text-properties place (1+ place)
                               '(face (bold font-lock-warning-face))
                               out)
          out))
 u-get-status ()
  (let* ((id (tabulated-list-get-id))
         (entry (and id (assoc id tabulated-list-entries))))
    (if entry
        (aref (cadr entry) 2)
      "")))

(defun package-archive-priority (archive)
  "Return the priority of ARCHIVE.
The archive priorities are specified in
`package-archive((pkg-desc (car entry))
            (status (aref (cadr entry) 2)))
        (cond ((member status '("installed" "dependency" "unsigned"))
               (push pkg-desc installed))
              ((member status '("available" "new"))
               (setq available (package--append-to-alist pkg-desc available))))))
    ;; Loop through list of installed packages, finding upgrades.
    (dolist (pkg-desc installed)
      (let* ((name (package-desc-name pkg-desc))
             (avail-pkg (cadr (assq name available))))
        (and avail-pkg
             (version-list-< (package-desc-priority-version pkg-desc)
             -mode-p 'package-menu-mode)
    (error "The current buffer is not a Package Menu"))
  (setq package-menu--mark-upgrades-pending nil)
  (let ((upgrades (package-menu--find-upgrades)))
    (if (null upgrades)
        (message "No packages to upgrade.")
      (widen)
      (save-excursion
        (goto-char (point-min))
        (while (not (eobp))
          (let* ((pkg-desc (tabulated-list-get-id))
                 (upgrade (cdr (assq (package-desc-name pkg-desc) upgrades))))
            (cond ((null upgrade)
                   (forward-line 1))
                  ((equal pkg-desc upgrade)
                   (plable version and a (D)elete flag on
the installed version.  A subsequent \\[package-menu-execute]
call will upgrade the package.
If there's an async refresh operation in progress, the flags will
be placed as part of `package-menu--post-refresh' instead of
immediately."
  (interactive)
  (if (not package--downloads-in-progress)
      (package-menu--mark-upgrades-1)
    (setq package-menu--mark-upgrades-pending t)
    (message "Waiting for refresh to finish...")))

(defun package-menu--list-to-prompt (packages)
  "Return a string listing PACKAGES that's usable in a prompt.
PACKAGES is a list of `package-desc' objecll-name (car packages))))))

(defun package-menu--prompt-transaction-p (delete install upgrade)
  "Prompt the user about DELETE, INSTALL, and UPGRADE.
DELETE, INSTALL, and UPGRADE are lists of `package-desc' objects.
Either may be nil, but not all."
  (y-or-n-p
   (concat
    (when delete "Delete ")
    (package-menu--list-to-prompt delete)
    (when (and delete install)
      (if upgra such
objects removed."
  (let* ((upg (cl-intersection install delete :key #'package-desc-name))
         (ins (cl-set-difference install upg :key #'package-desc-name))
         (del (cl-set-difference delete upg :key #'package-desc-name)))
    `((delete . ,del) (install . ,ins) (upgrade . ,upg))))

(defun package-menu--perform-transaction (install-list delete-list)
  "Install packages in INSTALL-LIST and delete DELETE-LIST."
  (if install-list
      (let ((status-format (format ":Installing %%d/%d"
                             (length install-list)))
            (i 0)
            (package-menu--transaction-status))
        (dolist (pkg install-list)
      (force-mode-line-update)
    (redisplay 'force)
    (dolist (elt (package--sort-by-dependence delete-list))
      (condition-case-unless-debug err
          (let ((inhibit-message package-menu-async))
            (package-delete elt nil 'nosave))
        (error (message "Error trying to delete `%s': %ge-selected-packages)))

(defun package-menu-execute (&optional noquery)
  "Perform marked Package Menu actions.
Packages marked for installation are downloaded and installed;
packages marked for deletion are removed.
Optional argument NOQUERY non-nil means do not ask the user to confirm."
  (interactive)
  (unless (derived-mode-p 'package-menu-mode)
    (error "The current buffer is not in Package Menu mode"))
  (let (inots
 e-list)
      (when (or noquery
                (package-menu--prompt-transaction-p .delete .install .upgrade))
        (let ((message-template
               (concat "Package menu: Operation %s ["
                       (when .delete  (format "Delet__ %s" (length .delete)))
                       (whenu: Operation finished.  %d packages %s"
                  (length removable)
                  (substitute-command-keys
                   "are no longer needed, type `\\[package-autoremove]' to remove them"))
              (message (replace-regexp-in-string "__" "ed" message-template)
                "finished"))))))))

(defun package-menu--version-predicate (A B)
  (let ((vA (or (aref (cadr A) 1)  '(0)))
        (vB (or (aref (cadr B) 1) '(0))))
   sA "installed") t)
          ((string= sB "installed") nil)
          ((string= sA "dependency") t)
          ((string= sB "dependency") nil)
          ((string= sA "unsigned") t)
          ((string= sB "unsigned") nil)
          ((string= sA "held") t)
          ((strdicate (A B)
  (string< (or (package-desc-archive (car A)) "")
           (or (package-desc-archive (car B)) "")))

(defun package-menu--populate-new-package-list ()
  "Decide which packages are new in `package-archives-contents'.
Store this list in `package-menu--new-package-list'."
  ;; Find which packages are new.
  (when package-menu--old-archive-contents
  sh ()
  "If there's a *Packages* buffer, revert it and check for new packages and upgrades.
Do nothing if there's no *Packages* buffer.
This function is called after `package-refresh-contents' and it
is added to `post-command-hook' by any function which alters the
package database (`package-install' and `package-delete').  When
run, it removes itself from `post-command-hook'."
  (remove-hook 'post-command-hook #'package-menu--post-refresh)
  (let ((buf (get-buffer "*Packages*")))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (package-menu--populate-new-package-list)
        (run-hooks 'tabu is called after `package-refresh-contents'."
  (let ((buf (get-buffer "*Packages*")))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (if package-menu--mark-upgrades-pending
            (package-menu--mark-upgrades-1)
          (package-menu--find-and-notify-upgrades))))))

;;;###autoload
(defun list-packages (&optional no-fetch)
  "Display a list of packages.
This first fetches the updated list of packages before
displaying, unless a prefix argument NO-FETCH is specified.
The list is displayed in a buffer named `*Packages*'."
  (interactive "P")
  (require 'finder-inf nil t)
  ;; Initialize the et-buffer-create "*Packages*")))
    (with-current-buffer buf
      (package-menu-mode)

      ;; Fetch the remote list of packages.
      (unless no-fetch (package-menu-refresh))

      ;; If we're not async, this would be redundant.
      (when package-menu-async
        (package-menu--generate nil t)))
    ;; The package menu buffer has keybindings.  Ifet-buffer-window buf)))
    (with-current-buffer buf
      (package-menu-mode)
      (package-menu--generate nil packages keywords))
    (if win
        (select-window win)
      (switch-to-buffer buf))))

;; package-menu--generate rebinds "q" on the fly, so we have to
;; hard-code the binding in the doc-string here.
(defun package-menu-filter (keyword)
  "Filter the *Packages* buffer.
Show only those items that relate to the specified KEYWORD.
KEYWORD can be a string or a list of strings.  If it is a list, a
package will be displayed if it matches any of the keywords.
Interactively, it is a list of strings separated by commas.
To restore the full package list, type `q'."
  (interactot fetch the updated list of packages before displaying.
The list is displayed in a buffer named `*Packages*'."
  (interactive)
  (list-packages t))

(provide 'package)

;;; package.el ends here