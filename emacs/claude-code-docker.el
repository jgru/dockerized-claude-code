;;; claude-code-docker.el --- Claude Code via Docker -*- lexical-binding: t; -*-

;; Integrates claude-code-ide with the dockerized claude-docker wrapper.
;; Supports named instances for parallel agents and an optional
;; non-dockerized ("bare") mode.

;;; Configuration

(defgroup claude-docker nil
  "Claude Code Docker integration."
  :group 'tools
  :prefix "claude-docker-")

(defcustom claude-docker-cli
  (expand-file-name "~/.local/bin/claude")
  "Path to the dockerized claude-docker wrapper."
  :type 'string)

(defcustom claude-docker-bare-cli "claude"
  "Path to the native (non-dockerized) Claude Code CLI."
  :type 'string)

(defcustom claude-docker-use-docker t
  "When non-nil use the Docker wrapper, otherwise run Claude Code natively."
  :type 'boolean)

(defcustom claude-docker-instances-dir
  (expand-file-name "~/.config/claude-devcontainer/instances/")
  "Directory where named instance state is stored."
  :type 'directory)

(defvar-local claude-docker-instance nil
  "Named instance for the current buffer/project.
Set interactively with `claude-docker-set-instance' or per-project
via .dir-locals.el:

  ((nil . ((claude-docker-instance . \"stan\"))))")

;;; Package setup

(add-to-list 'exec-path (expand-file-name "~/.local/bin"))
(setenv "PATH" (concat (expand-file-name "~/.local/bin") ":" (getenv "PATH")))

(use-package claude-code-ide
  :straight (:type git :host github :repo "manzaltu/claude-code-ide.el")
  :bind ("C-c C-'" . claude-code-ide-menu)
  :config
  (setq claude-code-ide-cli-path claude-docker-cli)
  (claude-code-ide-emacs-tools-setup))

;;; Instance helpers

(defun claude-docker--instance-names ()
  "Return list of existing instance names."
  (when (file-directory-p claude-docker-instances-dir)
    (cl-remove-if
     (lambda (f) (member f '("." "..")))
     (directory-files claude-docker-instances-dir nil "^[^.]"))))

(defun claude-docker--effective-cli ()
  "Return the CLI path based on `claude-docker-use-docker'."
  (if claude-docker-use-docker
      claude-docker-cli
    claude-docker-bare-cli))

(defun claude-docker--inject-flags (&rest _)
  "Set `claude-code-ide-cli-path' and inject instance flag before launch."
  (setq claude-code-ide-cli-path (claude-docker--effective-cli))
  (let ((base (or claude-code-ide-cli-extra-flags "")))
    ;; Strip any prior -i flag
    (setq base (string-trim (replace-regexp-in-string "-i +[^ ]+" "" base)))
    (setq claude-code-ide-cli-extra-flags
          (if (and claude-docker-instance claude-docker-use-docker)
              (string-trim (concat (format "-i %s" claude-docker-instance)
                                   " " base))
            base))))

(dolist (fn '(claude-code-ide claude-code-ide-continue claude-code-ide-resume))
  (advice-add fn :before #'claude-docker--inject-flags))

;;; Interactive commands

(defun claude-docker-set-instance (name)
  "Set the Claude instance name for the current buffer."
  (interactive
   (list (completing-read "Instance (empty for default): "
                          (claude-docker--instance-names) nil nil)))
  (setq-local claude-docker-instance (if (string-empty-p name) nil name))
  (message "Claude instance: %s" (or claude-docker-instance "default")))

(defun claude-docker-start (instance)
  "Start Claude with a named INSTANCE, completing from existing ones."
  (interactive
   (list (completing-read "Instance: "
                          (claude-docker--instance-names) nil nil)))
  (setq-local claude-docker-instance (if (string-empty-p instance) nil instance))
  (claude-code-ide))

(defun claude-docker-list-instances ()
  "Show all Claude instances in a buffer."
  (interactive)
  (let ((buf (get-buffer-create "*claude-instances*"))
        (cmd (concat claude-docker-cli " --list")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (shell-command-to-string cmd)))
      (special-mode))
    (display-buffer buf)))

(defun claude-docker-prune-instance (name)
  "Prune a stopped Claude instance by NAME."
  (interactive
   (list (completing-read "Prune instance: "
                          (claude-docker--instance-names) nil t)))
  (when (yes-or-no-p (format "Prune instance '%s'? " name))
    (message "%s"
             (string-trim
              (shell-command-to-string
               (format "%s -i %s --prune"
                       claude-docker-cli
                       (shell-quote-argument name)))))))

(defun claude-docker-toggle-docker ()
  "Toggle between dockerized and native Claude Code."
  (interactive)
  (setq claude-docker-use-docker (not claude-docker-use-docker))
  (message "Claude: %s" (if claude-docker-use-docker "docker" "native")))

;;; Project scaffolding

(defun claude-init-env ()
  "Create a .env template in the project root."
  (interactive)
  (let* ((root (or (vc-root-dir) default-directory))
         (env-file (expand-file-name ".env" root))
         (gitignore (expand-file-name ".gitignore" root)))
    (unless (file-exists-p env-file)
      (with-temp-file env-file
        (insert "GITHUB_TOKEN=\n"
                "# GITLAB_TOKEN=\n"
                "# GIT_AUTHOR_NAME=Your Name\n"
                "# GIT_AUTHOR_EMAIL=you@example.com\n"
                "# CLAUDE_FIREWALL=true\n")))
    (when (file-exists-p gitignore)
      (with-temp-buffer
        (insert-file-contents gitignore)
        (unless (string-match-p "^\\.env$" (buffer-string))
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert ".env\n")
          (write-region (point-min) (point-max) gitignore))))
    (find-file env-file)))

(provide 'claude-code-docker)
;;; claude-code-docker.el ends here
