;;; historian.el --- Persistently store selected minibuffer candidates -*- lexical-binding: t -*-

;; Copyright (C) 2017 PythonNut

;; Author: PythonNut <pythonnut@pythonnut.com>
;; Keywords: convenience, helm, ivy
;; Version: 20151013
;; URL: https://github.com/PythonNut/historian.el
;; Package-Requires: ((emacs "24.4"))

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Historian.el stores the results of completing-read and similar
;; functions persistently. This provides a way to give completion
;; candidates that are more frequently or more recently used a better
;; position in the candidates list.

;;; Code:

(defgroup historian nil
  "Persistently store selected minibuffer candidates"
  :group 'convenience
  :prefix "historian-")

(defvar historian-save-file (locate-user-emacs-file ".historian"))

(defcustom historian-history-length 10
  "Determines how many recently selected candidates Historian should remember."
  :type 'number
  :group 'historian)

(defcustom historian-save-file (locate-user-emacs-file ".historian")
  "File in which Historian saves its state between Emacs sessions."
  :type 'file
  :group 'historian)

(defcustom historian-enable-helm t
  "Determines whether to enable hooks for helm"
  :type 'boolean
  :group 'historian)

(defcustom historian-enable-ivy t
  "Determines whether to enable hooks for ivy"
  :type 'boolean
  :group 'historian)

(defvar historian--history-table)

(defun historian-push-item (key value)
  (prog1 value
    (puthash key
             (let ((old-value
                    (gethash key
                             historian--history-table
                             (cons (list)
                                   (make-hash-table :test #'equal)))))
               (push value (car old-value))
               (when (> (length (car old-value))
                        historian-history-length)
                 (setcar old-value
                         (let (res)
                           (dotimes (_ historian-history-length res)
                             (push (pop (car old-value)) res)))))
               (puthash value
                        (1+ (gethash value
                                     (cdr old-value)
                                     0))
                        (cdr old-value))
               old-value)
             historian--history-table)))

(defun historian--nadvice/completing-read (return)
  (historian-push-item last-command return))

(defun historian--nadvice/helm-comp-read (old-fun &rest args)
  (let ((historian-this-command this-command)
        (return (apply old-fun args)))
    (historian-push-item historian-this-command return)
    return))

(defun historian--nadvice/ivy-read (old-fun &rest args)
  (cl-letf* ((old-rfm (symbol-function #'read-from-minibuffer))
             ((symbol-function #'read-from-minibuffer)
              (lambda (&rest args)
                (historian-push-item this-command
                                     (apply old-rfm args)))))
    (apply old-fun args)))

(defun historian-save ()
  (interactive)
  (with-temp-file historian-save-file
    (insert (pp historian--history-table))))

(defun historian-load ()
  (interactive)
  (setq historian--history-table
        (if (file-exists-p historian-save-file)
            (car (read-from-string (with-temp-buffer
                                     (insert-file-contents historian-save-file)
                                     (buffer-string))))
          (make-hash-table))))

(define-minor-mode historian-mode
  "historian minor mode"
  :init-value nil
  :group 'historian
  :global t
  (if historian-mode
      (progn
        (historian-load)

        (advice-add 'completing-read :filter-return
                    #'historian--nadvice/completing-read)

        (when (and historian-enable-helm
                   (fboundp #'helm-comp-read))
          (advice-add 'helm-comp-read :around
                      #'historian--nadvice/helm-comp-read))

        (when (and historian-enable-ivy
                   (fboundp #'ivy-read))
          (advice-add 'ivy-read :around
                      #'historian--nadvice/ivy-read))

        (add-hook 'kill-emacs-hook #'historian-save))

    (historian-save)

    (advice-remove 'completing-read #'historian--nadvice/completing-read)
    (advice-remove 'helm-comp-read #'historian--nadvice/helm-comp-read)
    (advice-remove 'ivy-read #'historian--nadvice/ivy-read)

    (remove-hook 'kill-emacs-hook #'historian-save)))

(provide 'historian)

;;; historian.el ends here
