;;; rinari.el --- Rinari Is Not A Rails IDE

;; Copyright (C) 2008 Phil Hagelberg, Eric Schulte

;; Authors: Phil Hagelberg, Eric Schulte
;; URL: http://rinari.rubyforge.org
;; Version: 2.0
;; Created: 2006-11-10
;; Keywords: ruby, rails, project, convenience, web
;; EmacsWiki: Rinari

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; Rinari Is Not A Ruby IDE.

;; Well, ok it kind of is. Rinari is a set of Emacs Lisp modes that is
;; aimed towards making Emacs into a top-notch Ruby and Rails
;; development environment.

;; Copy the directory containing this file into your Emacs lisp
;; directory, assumed here to be ~/.emacs.d. Add these lines of code
;; to your .emacs file:

;; (add-to-list 'load-path "~/.emacs.d/rinari")
;; (require 'rinari)

;; See TODO file in this directory.

;;; Code:
(let ((this-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path this-dir)
  (add-to-list 'load-path (expand-file-name "util" this-dir))
  (add-to-list 'load-path (expand-file-name "util/jump" this-dir)))
(require 'ruby-mode)
(require 'inf-ruby)
(require 'ruby-compilation)
(require 'jump)
(require 'cl)

(defcustom rinari-browse-url-func
  'browse-url
  "`browse-url' function used by `rinari-browse-view'.")

(defcustom rinari-tags-file-name
  "TAGS"
  "Path to your TAGS file inside of your rails project.  See `tags-file-name'.")

(defvar rinari-minor-mode-hook nil
  "*Hook for customising Rinari.")

(defadvice ruby-run-w/compilation (around rinari-run-w/compilation activate)
  "Set default directory to the root of the rails application
  before running ruby processes."
  (let ((default-directory (or (rinari-root) default-directory)))
    ad-do-it
    (rinari-launch)))

(defadvice ruby-rake-w/compilation (around rinari-rake-w/compilation activate)
  "Set default directory to the root of the rails application
  before running rake processes."
  (let ((default-directory (or (rinari-root) default-directory)))
    ad-do-it
    (rinari-launch)))

(defun rinari-parse-yaml ()
  (let ((start (point))
	(end (save-excursion (re-search-forward "^$" nil t) (point)))
	alist)
    (while (and (< (point) end)
		(re-search-forward "^ *\\(.*\\): \\(.*\\)$" nil t))
      (setf alist (cons (cons (match-string 1) (match-string 2)) alist)))
    alist))

(defun rinari-root (&optional dir)
  (or dir (setq dir default-directory))
  (if (file-exists-p (concat dir "config/environment.rb"))
      dir
    (unless (equal dir "/")
      (rinari-root (expand-file-name (concat dir "../"))))))

;;--------------------------------------------------------------------------------
;; user functions

(defun rinari-rake (&optional task edit-cmd-args)
  "Tab completion selection of a rake task to execute with the
output dumped to a compilation buffer allowing jumping between
errors and source code.  With optional prefix argument allows
editing of the rake command arguments."
  (interactive "P")
  (ruby-rake-w/compilation task edit-cmd-args))

(defun rinari-script (&optional script)
  "Tab completing selection of a script from the script/
directory of the rails application."
  (interactive)
  (let* ((root (rinari-root))
	 (script (or script
		     (completing-read "Script: " (directory-files (concat root "script") nil "^[^.]"))))
	 (ruby-compilation-error-regexp-alist ;; for jumping to newly created files
	  (if (equal script "generate")
	      '(("^ +\\(exists\\|create\\) +\\([^[:space:]]+\\.rb\\)" 2 3))
	    ruby-compilation-error-regexp-alist))
	 (script (concat "script/" script " ")))
    (ruby-run-w/compilation (concat root script (read-from-minibuffer script)))))

(defun rinari-test (&optional edit-cmd-args)
  "Test the current ruby function.  If current function is not a
test, then try to jump to the related test using
`rinari-find-test'.  Dump output to a compilation buffer allowing
jumping between errors and source code.  With optional prefix
argument allows editing of the test command arguments."
  (interactive "P")
  (or (string-match "test" (or (ruby-add-log-current-method)
			       (file-name-nondirectory (buffer-file-name))))
      (rinari-find-test))
  (let* ((funname (ruby-add-log-current-method))
	 (fn (and funname
		  (string-match "#\\(.*\\)" funname)
		  (match-string 1 funname)))
	 (path (buffer-file-name))
	 (default-command (if fn
			      (concat path " --name /" fn "/")
			    path))
	 (command (if edit-cmd-args
		      (read-string "Run w/Compilation: " default-command)
		    default-command)))
    (if path (ruby-run-w/compilation command)
      (message "no test available"))))

(defun rinari-console (&optional edit-cmd-args)
  "Run script/console in a compilation buffer, with command
history and links between errors and source code.  With optional
prefix argument allows editing of the console command arguments."
  (interactive "P")
  (let* ((script (concat (rinari-root) "script/console"))
	 (command (if edit-cmd-args
		      (read-string "Run Ruby: " (concat script " "))
		    script)))
    (run-ruby command)
    (save-excursion (pop-to-buffer "*ruby*")
      (set (make-local-variable 'inferior-ruby-first-prompt-pattern) "^>> ")
      (set (make-local-variable 'inferior-ruby-prompt-pattern) "^>> ")
      (rinari-launch))))

(defun rinari-sql ()
  "Browse the application's database.  Looks up login information
from your conf/database.sql file."
  (interactive)
  (flet ((sql-name (env) (format "*%s-sql*" env)))
    (let* ((environment (or (getenv "RAILS_ENV") "development"))
	   (sql-buffer (get-buffer (sql-name environment))))
      (if sql-buffer
	  (pop-to-buffer sql-buffer)
	(let* ((database-alist (save-excursion
				 (with-temp-buffer
				   (insert-file (concat (rinari-root)
							"/config/database.yml"))
				   (goto-char (point-min))
				   (re-search-forward (concat "^" environment ":"))
				   (rinari-parse-yaml))))
	       (adapter (or (cdr (assoc "adapter" database-alist)) "sqlite"))
	       (sql-user (or (cdr (assoc "username" database-alist)) "root"))
	       (sql-password (or (cdr (assoc "password" database-alist)) ""))
	       (sql-database (or (cdr (assoc "database" database-alist))
				 (concat (file-name-nondirectory (rinari-root))
					 "_" environment)))
	       (server (or (cdr (assoc "host" database-alist)) "localhost"))
	       (port (cdr (assoc "port" database-alist)))
	       (sql-server (if port (concat server ":" port) server)))
	  (if (string-match "sqlite" adapter) (setf adapter "sqlite"))
	  (eval (list (intern (concat "sql-" adapter))))
	  (rename-buffer (sql-name environment)) (rinari-launch))))))

(defun rinari-web-server (&optional edit-cmd-args)
  "Run script/server.  Dump output to a compilation buffer
allowing jumping between errors and source code.  With optional
prefix argument allows editing of the server command arguments."
  (interactive "P")
  (let* ((default-directory (rinari-root))
	 (script (concat (rinari-root) "script/server"))
	 (command (if edit-cmd-args
		      (read-string "Run Ruby: " (concat script " "))
		    script)))
    (ruby-run-w/compilation command)))

(defun rinari-browse-url ()
  "Browse the url of the current view, controller, test, or model
with `rinari-browse-url-func' which defaults to `browse-url'."
  (interactive)
  (unless (equal :view (rinari-whats-my-type))
    (rinari-find-view))
  (let* ((path (buffer-file-name))
	 (route (and (string-match "app/views/\\(.+\\)\.r[ebhtml]+" path)
		     (match-string 1 path)))
	 (port (or () ;; guess port (or not)
		   "3000"))
	 (server (or () ;; guess server (or not)
		     "localhost"))
	 (base (concat server ":" port "/" route))
	 (url (read-from-minibuffer "url: " (concat base "/"))))
    (eval (list rinari-browse-url-func url))))

(defun rinari-insert-erb-skeleton (no-equals)
  "Insert an erb skeleton at point, with optional prefix argument
don't include an '='."
  (interactive "P")
  (insert "<%") (unless no-equals (insert "=")) (insert "  %>")
  (backward-char 3))

(defun rinari-rgrep (&optional arg)
  "Search through the rails project for a string or `regexp'.
With optional prefix argument just run `rgrep'."
  (interactive "P")
  (grep-compute-defaults)
  (if arg (call-interactively 'rgrep)
    (funcall 'rgrep (read-from-minibuffer "search for: ")
	     "*.rb *.rhtml *.yml *.erb" (rinari-root))))

;;--------------------------------------------------------------------
;; rinari movement using jump.el

(defun rinari-generate (type name)
  (message (shell-command-to-string
	    (format "ruby %sscript/generate %s %s" (rinari-root) type
		    (read-from-minibuffer (format "create %s: " type) name)))))

(defvar rinari-ruby-hash-regexp
  "\\(:[^[:space:]]*?\\)[[:space:]]*\\(=>[[:space:]]*[\"\':]?\\([^[:space:]]*?\\)[\"\']?[[:space:]]*\\)?[,){}\n]"
  "Regexp to match subsequent key => value pairs of a ruby hash.")

(defun rinari-ruby-values-from-render (controller action)
  "Adjusts CONTROLLER and ACTION acording to keyword arguments in
the hash at `point', then return (CONTROLLER . ACTION)"
  (let ((end (save-excursion
	       (re-search-forward "[^,{(]$" nil t)
	       (+ 1 (point)))))
    (save-excursion
      (while (and (< (point) end)
		  (re-search-forward rinari-ruby-hash-regexp end t))
	(if (> (length (match-string 3)) 1)
	    (case (intern (match-string 1))
	      (:partial (setf action (concat "_" (match-string 3))))
	      (:action  (setf action (match-string 3)))
	      (:controller (setf controller (match-string 3)))))))
    (cons controller action)))

(defun rinari-which-render (renders)
  (let ((path (jump-completing-read
	       "Follow: "
	       (mapcar (lambda (lis)
			 (concat (car lis) "/" (cdr lis)))
		       renders))))
    (string-match "\\(.*\\)/\\(.*\\)" path)
    (cons (match-string 1 path) (match-string 2 path))))

(defun rinari-follow-controller-and-action (controller action)
  "Follow the current controller-and-action through all of the
renders and redirects to find the final controller or view."
  (save-excursion ;; if we can find the controller#action pair
    (if (and (jump-to-path (format "app/controllers/%s_controller.rb#%s" controller action))
	     (equalp (jump-method) action))
	(let ((start (point)) ;; demarcate the borders
	      (renders (list (cons controller action))) render view)
	  (ruby-forward-sexp)
	  ;; collect redirection options and pursue
	  (while (re-search-backward "re\\(?:direct_to\\|nder\\)" start t)
	    (add-to-list 'renders (rinari-ruby-values-from-render controller action)))
	  (let ((render (if (equalp 1 (length renders))
			    (car renders)
			  (rinari-which-render renders))))
	    (if (and (equalp (cdr render) action)
		     (equalp (car render) controller))
		(list controller action) ;; directed to here so return
	      (rinari-follow-controller-and-action (or (car render)
						       controller)
						   (or (cdr render)
						       action)))))
      ;; no controller entry so return
      (list controller action))))

(setf
 rinari-jump-schema
 '((model
    "m"
    (("app/controllers/\\1_controller.rb#\\2"  . "app/models/\\1.rb#\\2")
     ("app/views/\\1/.*"                       . "app/models/\\1.rb")
     ("app/helpers/\\1_helper.rb"              . "app/models/\\1.rb")
     ("db/migrate/.*create_\\1.rb"             . "app/models/\\1.rb")
     ("test/functional/\\1_controller_test.rb" . "app/models/\\1.rb")
     ("test/unit/\\1_test.rb#test_\\2"         . "app/models/\\1.rb#\\2")
     ("test/unit/\\1_test.rb"                  . "app/models/\\1.rb")
     ("test/fixtures/\\1.yml"                  . "app/models/\\1.rb")
     (t                                        . "app/models/"))
    (lambda (path)
      (rinari-generate "model"
		       (and (string-match ".*/\\(.+?\\)\.rb" path)
			    (match-string 1 path)))))
   (controller
    "c"
    (("app/models/\\1.rb"                      . "app/controllers/\\1_controller.rb")
     ("app/views/\\1/\\2\\..*"                 . "app/controllers/\\1_controller.rb#\\2")
     ("app/helpers/\\1_helper.rb"              . "app/controllers/\\1_controller.rb")
     ("db/migrate/.*create_\\1.rb"             . "app/controllers/\\1_controller.rb")
     ("test/functional/\\1_controller_test.rb" . "app/controllers/\\1_controller.rb")
     ("test/unit/\\1_test.rb#test_\\2"         . "app/controllers/\\1_controller.rb#\\2")
     ("test/unit/\\1_test.rb"                  . "app/controllers/\\1_controller.rb")
     ("test/fixtures/\\1.yml"                  . "app/controllers/\\1_controller.rb")
     (t                                        . "app/controllers/"))
    (lambda (path)
      (rinari-generate "model"
		       (and (string-match ".*/\\(.+?\\)_controller\.rb" path)
			    (match-string 1 path)))))
   (view
    "v"
    (("app/models/\\1.rb"                      . "app/views/\\1/.*")
     ((lambda () ;; find the controller/view
	(rinari-follow-controller-and-action
	 (let ((file (file-name-nondirectory (buffer-file-name))))
	   (and (string-match "^\\(.*\\)_controller.rb" file)
		(match-string 1 file)));; controller
	 (let ((method (ruby-add-log-current-method))) ;; action
	   (and (string-match "#\\(.*\\)" method) (match-string 1 method)))))
                                               . "app/views/\\1/\\2\\..*")
     ("app/helpers/\\1_helper.rb"              . "app/views/\\1/.*")
     ("db/migrate/.*create_\\1.rb"             . "app/views/\\1/.*")
     ("test/functional/\\1_controller_test.rb" . "app/views/\\1/.*")
     ("test/unit/\\1_test.rb#test_\\2"         . "app/views/\\1/_?\\2.*")
     ("test/fixtures/\\1.yml"                  . "app/views/\\1/.*")
     (t                                        . "app/views/.*"))
    nil)
   (test
    "t"
    (("app/models/\\1.rb#\\2"                  . "test/unit/\\1_test.rb#test_\\2")
     ("app/controllers/\\1.rb#\\2"             . "test/functional/\\1_test.rb#test_\\2")
     ("app/views/\\1/_?\\2\\..*"               . "test/functional/\\1_controller_test.rb#test_\\2")
     ("app/helpers/\\1_helper.rb"              . "test/functional/\\1_controller_test.rb")
     ("db/migrate/.*create_\\1.rb"             . "test/unit/\\1_test.rb")
     ("test/functional/\\1_controller_test.rb" . "test/unit/\\1_test.rb")
     ("test/unit/\\1_test.rb"                  . "test/functional/\\1_controller_test.rb")
     (t                                        . "test/.*"))
    nil)
   (fixture
    "x"
    (("app/models/\\1.rb"                      . "test/fixtures/\\1.yml")
     ("app/controllers/\\1_controller.rb"      . "test/fixtures/\\1.yml")
     ("app/views/\\1/.*"                       . "test/fixtures/\\1.yml")
     ("app/helpers/\\1_helper.rb"              . "test/fixtures/\\1.yml")
     ("db/migrate/.*create_\\1.rb"             . "test/fixtures/\\1.yml")
     ("test/functional/\\1_controller_test.rb" . "test/fixtures/\\1.yml")
     ("test/unit/\\1_test.rb"                  . "test/fixtures/\\1.yml")
     (t                                        . "test/fixtures/"))
    nil)
   (helper
    "h"
    (("app/models/\\1.rb"                      . "app/helpers/\\1_helper.rb")
     ("app/controllers/\\1_controller.rb"      . "app/helpers/\\1_helper.rb")
     ("app/views/\\1/.*"                       . "app/helpers/\\1_helper.rb")
     ("app/helpers/\\1_helper.rb"              . "app/helpers/\\1_helper.rb")
     ("db/migrate/.*create_\\1.rb"             . "app/helpers/\\1_helper.rb")
     ("test/functional/\\1_controller_test.rb" . "app/helpers/\\1_helper.rb")
     ("test/unit/\\1_test.rb#test_\\2"         . "app/helpers/\\1_helper.rb#\\2")
     ("test/unit/\\1_test.rb"                  . "app/helpers/\\1_helper.rb")
     (t                                        . "app/helpers/"))
    nil)
   (migration
    "i"
    (("app/controllers/\\1_controller.rb"      . "db/migrate/.*create_\\1.rb")
     ("app/views/\\1/.*"                       . "db/migrate/.*create_\\1.rb")
     ("app/helpers/\\1_helper.rb"              . "db/migrate/.*create_\\1.rb")
     ("app/models/\\1.rb"                      . "db/migrate/.*create_\\1.rb")
     ("test/functional/\\1_controller_test.rb" . "db/migrate/.*create_\\1.rb")
     ("test/unit/\\1_test.rb#test_\\2"         . "db/migrate/.*create_\\1.rb#\\2")
     ("test/unit/\\1_test.rb"                  . "db/migrate/.*create_\\1.rb")
     (t                                        . "db/migrate/"))
    (lambda (path)
      (rinari-generate "migration"
		       (and (string-match ".*create_\\(.+?\\)\.rb" path)
			    (match-string 1 path)))))
   (environment "e" ((t . "config/environments/")) nil)
   (configuration "n" ((t . "config/")) nil)
   (script "s" ((t . "script/")) nil)
   (lib "l" ((t . "lib/")) nil)
   (log "o" ((t . "log/")) nil)
   (worker "w" ((t . "lib/workers/")) nil)
   (public "p" ((t . "public/")) nil)
   (stylesheet "y" ((t . "public/stylesheets/.*")) nil)
   (javascript "j" ((t . "public/javascripts/.*")) nil)
   (plugin "l" ((t . "vendor/plugins/")) nil)
   (file-in-project "f" ((t . ".*")) nil)))

(mapcar
 (lambda (type)
   (let ((name (first type))
	 (specs (third type))
	 (make (fourth type)))
     (eval `(defjump
	      (quote ,(read (format "rinari-find-%S" name)))
	      (quote ,specs)
	      'rinari-root
	      ,(format "Go to the most logical %S given the current location" name)
	      ,(if make `(quote ,make))
	      'ruby-add-log-current-method))))
 rinari-jump-schema)

;;--------------------------------------------------------------------
;; minor mode and keymaps

(defvar rinari-minor-mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "Key map for Rinari minor mode.")

(defun rinari-bind-key-to-func (key func)
  (eval `(define-key rinari-minor-mode-map 
	   ,(format "\C-c;%s" key) ,func))
  (eval `(define-key rinari-minor-mode-map 
	   ,(format "\C-c'%s" key) ,func)))

(defvar rinari-minor-mode-keybindings
  '(("s" . 'rinari-script)
    ("e" . 'rinari-insert-erb-skeleton) ("t" . 'rinari-test)
    ("r" . 'rinari-rake)                ("c" . 'rinari-console)
    ("w" . 'rinari-web-server)          ("g" . 'rinari-rgrep)
    ("b" . 'rinari-browse-url)          ("q" . 'rinari-sql))
  "alist mapping of keys to functions in `rinari-minor-mode'")

(mapcar (lambda (el) (rinari-bind-key-to-func (car el) (cdr el)))
	(append (mapcar (lambda (el)
			  (cons (concat "f" (second el))
				(read (format "'rinari-find-%S" (first el)))))
			rinari-jump-schema)
		rinari-minor-mode-keybindings))

(defun rinari-launch ()
  "Run `rinari-minor-mode' if inside of a rails projecct,
otherwise turn `rinari-minor-mode' off if it is on."
  (interactive)
  (let* ((root (rinari-root)) (r-tags-path (concat root rinari-tags-file-name)))
    (when root
      (set (make-local-variable 'tags-file-name)
           (and (file-exists-p r-tags-path) r-tags-path))
      (run-hooks 'rinari-minor-mode-hook)
      (rinari-minor-mode t))))

(defvar rinari-major-modes
  '('find-file-hook 'mumamo-after-change-major-mode-hook 'dired-mode-hook)
  "Major Modes from which to launch Rinari.")

(mapcar (lambda (hook)
	  (eval `(add-hook ,hook
			   (lambda () (rinari-launch)))))
	rinari-major-modes)

(defadvice cd (after rinari-on-cd activate)
  "Active/Deactive rinari-minor-node when changing into and out
  of raills project directories."
  (rinari-launch))

;;;###autoload
(define-minor-mode rinari-minor-mode
  "Enable Rinari minor mode providing Emacs support for working
with the Ruby on Rails framework."
  nil
  " Rinari"
  rinari-minor-mode-map)

(provide 'rinari)
;;; rinari.el ends here