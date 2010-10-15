;;; workgroups-mode.el --- workgroups for windows

;; Copyright (C) 2010 tlh <thunkout@gmail.com>

;; File:      workgroups-mode.el
;; Author:    tlh <thunkout@gmail.com>
;; Created:   2010-07-22
;; Version:   1.0
;; Keywords:  window persistence window-configuration

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:
;;
;;   workgroups-mode.el is a window configuration persistence minor
;;   mode for GNU Emacs.  It allows you to persist window
;;   configurations, called "workgroups" because it's shorter and
;;   funnier, between sessions.  workgroups-mode saves the window
;;   layout of the current frame, as well as each window's buffer's
;;   filename if it's visiting a file, or its buffername otherwise.
;;   And that's it. It doesn't try to save complicated information
;;   about the buffer, like major or minor modes.  If you save
;;   workgroups that include things like erc or gnus buffers, you
;;   should launch those applications and buffers again in your next
;;   session before restoring the workgroup that includes
;;   them. Nothing bad will happen otherwise, of course.
;;   workgroups-mode will just default to a buffer that already
;;   exists, like *scratch*.
;;
;;   `workgroups-list' contains all the currently available
;;   workgroups.  You can switch to workgroups (i.e. restore window
;;   configurations), bury them, go to the previous or next workgroup
;;   circularly, etc.  `workgroups-save' saves `workgroups-list' to a
;;   file, which can then be loaded in another session.  Workgroups
;;   are added to `workgroups-list' by calling `workgroups-create',
;;   removed by calling `workgroups-kill', and can be moved to the end
;;   of `workgroups-list' by calling `workgroups-bury'.  In general,
;;   operations on workgroups and `workgroups-list' behave as
;;   similarly to buffers and buffer-lists as possible.
;;

;;; Installation:
;;
;;   - Put `workgroups-mode.el' somewhere on your emacs load path
;;
;;   - Add this line to your .emacs file:
;;
;;     (require 'workgroups-mode)
;;

;;; Configuration:
;;
;;   To turn on workgroups-mode, either issue the command:
;;
;;     M-x workgroups-mode
;;
;;   Or put this in your .emacs file:
;;
;;     (workgroups-mode t)
;;
;;   To start off, you should add a few workgroups.  When your frame
;;   is in a state that you'd like to save, run the command
;;   `workgroups-create', and give the workgroup a name when prompted.
;;   Once you've added a few workgroups with `workgroups-create', you
;;   should save them to a file with `workgroups-save'.  You can
;;   designate this file to be automatically loaded when
;;   workgroups-mode is started by setting `workgroups-default-file'
;;   like so:
;;
;;     (setq workgroups-default-file "/path/to/workgroups/file")
;;
;;   If `workgroups-autoswitch' is non-nil, the first workgroup in a
;;   file will automatically be switched to when the file is loaded:
;;
;;     (setq workgroups-autoswitch t)
;;
;;   With these two options set, workgroups mode will automatically
;;   load the default file and switch to the first workgroup in it at
;;   emacs startup.
;;
;;   Check the documentation of the customizable variables below for
;;   more configuration options.
;;

;;; TODO:
;;
;;  - Switch just the window structure, keeping the current buffers,
;;    as far as that is possible with mismatch.
;;
;;  - Multi-frame support. Need to update mode-line for this, too.
;;


;;; Code:

(require 'cl)


;;; customization

(defgroup workgroups nil
  "Workgroup for Windows -- A simple window configuration
persistence mode."
  :group 'convenience
  :version "1.0")

(defcustom workgroups-default-file nil
  "File to load automatically when `workgroups-mode' is enabled.
If you want this to be loaded at emacs startup, make sure to set
it before calling `workgroups-mode'."
  :type 'file
  :group 'workgroups)

(defcustom workgroups-default-buffer "*scratch*"
  "Name of the default buffer used in `workgroups-create', and
other functions."
  :type 'string
  :group 'workgroups)

(defcustom workgroups-switch-hook nil
  "Hook run whenever a workgroup is switched to."
  :type 'hook
  :group 'workgroups)

(defcustom workgroups-autoswitch t
  "Non-nil means automatically switch to the first workgroup when
a file is loaded."
  :type 'boolean
  :group 'workgroups)

(defcustom workgroups-autosave nil
  "Non-nil means automatically save `workgroups-list' to
`workgroups-file' whenever `workgroups-list' is modified."
  :type 'boolean
  :group 'workgroups)

(defcustom workgroups-query-save-on-exit t
  "When non-nil, offer to save `workgroups-list' on exit if
`workgroups-dirty' in non-nil."
  :type 'boolean
  :group 'workgroups)

(defcustom workgroups-confirm-kill nil
  "Request confirmation before killing a workgroup when non-nil,
don't otherwise."
  :type 'boolean
  :group 'workgroups)


;;; non-customizable variables

(defvar workgroups-file-identifier '-*-workgroups-*-
  "Symbol identifying a workgroups file.")

(defvar workgroups-file nil
  "Current workgroups file.")

(defvar workgroups-list nil
  "Current list of workgroups.")

(defvar workgroups-current nil
  "Current workgroup.")

(defvar workgroups-previous nil
  "Previous workgroup.")

(defvar workgroups-dirty nil
  "Non-nil when there are unsaved changes.")

(defvar workgroups-kill-ring nil
  "List of killed configs.")

(defvar workgroups-kill-ring-pos 0
  "Position in `workgroups-kill-ring' during sequential yanks.")

(defvar workgroups-kill-ring-size 1000
  "Maximum number of configs `workgroups-kill-ring' can hold.")

(defvar workgroups-mode-line-on t
  "Toggles mode-line display.")

(defvar workgroups-mode-line-string "[unset]"
  "String displayed in the mode-line.")


;;; utils

(defun workgroups-next-util (elt lst)
  "Return elt after ELT in LST, or nil."
  (cadr (member elt lst)))

(defun workgroups-prev-util (elt lst)
  "Return elt before ELT in LST, or nil."
  (workgroups-next-util elt (reverse lst)))

(defun workgroups-cnext (elt lst)
  "Return elt after ELT in LIST, or car of LIST."
  (or (workgroups-next-util elt lst)
      (car lst)))

(defun workgroups-cprev (elt lst)
  "Return elt before ELT in LST, or car of last of LST."
  (or (workgroups-prev-util elt lst)
      (car (last lst))))

(defun workgroups-take (lst n)
  "Return a list of the first N elts in LST.
Iterative to prevent stack overflow."
  (let (acc)
    (while (and lst (> n 0))
      (decf n)
      (push (pop lst) acc))
    (nreverse acc)))

(defun workgroups-list-insert (elt n lst)
  "Insert ELT into LST at N."
  (append (workgroups-take lst n)
          (cons elt (nthcdr n lst))))

(defun workgroups-window-list (&optional frame)
  "Flatten `window-tree' into a stable list.
`window-list' can't be used because its order isn't stable."
  (flet ((inner (obj) (if (atom obj) (list obj)
                        (mapcan 'inner (cddr obj)))))
    (inner (car (window-tree (or frame (selected-frame)))))))

(defun workgroups-swap-util (elt1 elt2 lst)
  "Return a copy of LST with ELT1 with ELT2 swapped."
  (let* ((lst (copy-list lst))
         (l1  (member elt1 lst))
         (l2  (member elt2 lst)))
    (unless (and l1 l2)
      (error "ELT1 and ELT2 aren't present in LST."))
    (setcar l1 elt2)
    (setcar l2 elt1)
    lst))


;;; general

(defun workgroups-file (&optional noerror)
  "Return `workgroups-file'."
  (or workgroups-file
      (unless noerror
        (error "`workgroups-file' is unset."))))

(defun workgroups-list (&optional noerror)
  "Return `workgroups-list'."
  (or workgroups-list
      (unless noerror
        (error "No workgroups are defined."))))

(defun workgroups-get-workgroup (name &optional noerror)
  "Return workgroup named NAME."
  (or (assoc name (workgroups-list noerror))
      (unless noerror
        (error "There is no workgroup named %S" name))))

(defun workgroups-current (&optional noerror)
  "Return `workgroups-current'."
  (or workgroups-current
      (unless noerror
        (error "No current workgroup."))))

(defun workgroups-previous (&optional noerror)
  "Return `workgroups-previous'."
  (or workgroups-previous
      (unless noerror
        (error "No previous workgroups."))))


;; names

(defun workgroups-set-name (workgroup name)
  "Rename WORKGROUP to NAME."
  (setcar workgroup name))

(defun workgroups-name (workgroup)
  "Return the name of WORKGROUP."
  (car workgroup))

(defun workgroups-names (&optional noerror)
  "Return list of workgroups names."
  (mapcar 'workgroups-name (workgroups-list noerror)))


;;; saving and loading

(defun workgroups-save (&optional file)
  "Save FILE or `workgroups-file'."
  (let ((file (or file (workgroups-file))))
    (with-temp-buffer
      (insert (format "%s%S"
                      workgroups-file-identifier
                      (workgroups-list)))
      (write-file file))
    (setq workgroups-dirty nil
          workgroups-file  file)))

(defun workgroups-load (&optional file)
  "Load FILE or `workgroups-file'."
  (let ((file (or file (workgroups-file))))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (unless (eq (read (current-buffer)) workgroups-file-identifier)
        (error "%S is not a workgroups file."))
      (setq workgroups-list (read (current-buffer))))
    (setq workgroups-current  nil
          workgroups-previous nil
          workgroups-dirty    nil
          workgroups-file     file)))


;;; destructive ops

(defun workgroups-mark-dirty ()
  "`workgroups-save-file' when `workgroups-autosave' is non-nil."
  (setq workgroups-dirty t)
  (when workgroups-autosave (workgroups-save)))

(defun workgroups-add (workgroup &optional pos)
  "Add WORKGROUP at POS in or end of `workgroups-list'."
  (let ((wl (workgroups-list t)))
    (setq workgroups-list
          (workgroups-list-insert workgroup (length wl) wl))
    (workgroups-mark-dirty)))

(defun workgroups-delete (workgroup)
  "Remove WORKGROUP from `workgroups-list'."
  (let ((wl (workgroups-list)))
    (when (eq workgroup (workgroups-current t))
      (setq workgroups-current nil))
    (when (eq workgroup (workgroups-previous t))
      (setq workgroups-previous nil))
    (setq workgroups-list (remove workgroup wl))
    (workgroups-mark-dirty)))


;; base and working configs

(defun workgroups-set-base-config (workgroup config)
  "Set the base config of WORKGROUP to CONFIG."
  (setcar (cddr workgroup) config)
  (workgroups-mark-dirty))

(defun workgroups-base-config (workgroup)
  "Return the base config of WORKGROUP."
  (or (nth 2 workgroup)))

(defun workgroups-set-working-config (workgroup config)
  "Set the working config of WORKGROUP to CONFIG."
  (setcar (cdr workgroup) config))

(defun workgroups-working-config (workgroup)
  "Return the working config of WORKGROUP."
  (or (nth 1 workgroup)))


;;; window config making

(defun workgroups-wprop (key window)
  "Return value of KEY in workgroups WINDOW, or nil."
  (cdr (assoc key (cdr window))))

(defun workgroups-make-window (winobj)
  "Make a workgroups window object from WINOBJ.
WINOBJ is an Emacs window object."
  (with-current-buffer (window-buffer winobj)
    (let ((p (point)) (edges (window-edges winobj)))
      `(:window
        (:fname   .  ,(buffer-file-name))
        (:bname   .  ,(buffer-name))
        (:width   .  ,(- (nth 2 edges) (nth 0 edges)))
        (:height  .  ,(window-height winobj))
        (:point   .  ,(if (eq p (point-max)) :max p))
        (:wstart  .  ,(window-start winobj))))))

(defun workgroups-make-config (&optional frame)
  "Make a window config from FRAME or `selected-frame'."
  (let ((f (or frame (selected-frame))))
    (flet ((inner (obj) (etypecase obj
                          (window (workgroups-make-window obj))
                          (cons `(,@(workgroups-take obj 2)
                                  ,@(mapcar 'inner (cddr obj)))))))
      `(,(mapcar (lambda (p) (frame-parameter f p)) '(left top width height))
        ,(position (selected-window) (workgroups-window-list f))
        ,(inner (car (window-tree f)))))))

(defun workgroups-make-default-config (&optional buffer)
  "Return a new default config."
  (save-window-excursion
    (delete-other-windows)
    (switch-to-buffer (or buffer workgroups-default-buffer))
    (workgroups-make-config)))


;;; workgroup making

(defun workgroups-make-workgroup (name config &optional working)
  "Make a workgroup named NAME from FRAME or `selected-frame'."
  (list name (or working config) config))

(defun workgroups-make-current-workgroup (name)
  "Return a new workgroup from the current window configuration."
  (workgroups-make-workgroup
   name (workgroups-make-config)))

(defun workgroups-make-default-workgroup (name &optional buffer)
  "Return a new default workgroup named NAME."
  (workgroups-make-workgroup
   name (workgroups-make-default-config buffer)))


;;; window config restoring

(defun workgroups-window-p (window)
  "t if WINDOW is a workgroups window, nil otherwise."
  (and (consp window) (eq :window (car window))))

(defun workgroups-window-width (window)
  "Return the width of WINDOW."
  (if (workgroups-window-p window)
      (workgroups-wprop :width window)
    (let ((coords (cadr window)))
      (- (nth 2 coords) (nth 0 coords)))))

(defun workgroups-window-height (window)
  "Return the height of WINDOW."
  (if (workgroups-window-p window)
      (workgroups-wprop :height window)
    (let ((coords (cadr window)))
      (- (nth 3 coords) (nth 1 coords)))))

(defun workgroups-restore-window (window)
  "Restore WINDOW's state in `selected-window'."
  (let ((fname  (workgroups-wprop :fname  window))
        (bname  (workgroups-wprop :bname  window))
        (point  (workgroups-wprop :point  window))
        (wstart (workgroups-wprop :wstart window)))
    (and fname (file-exists-p fname) (find-file fname))
    (and bname (get-buffer bname) (switch-to-buffer bname))
    (set-window-start (selected-window) wstart t)
    (goto-char (if (eq point :max) (point-max) point))
    (when (>= wstart (point-max)) (recenter))))

(defun workgroups-restore-config (config &optional frame)
  "Restore CONFIG in FRAME or `selected-frame'."
  (flet ((inner (obj)
                (cond ((workgroups-window-p obj)
                       (workgroups-restore-window obj)
                       (other-window 1))
                      (t (dolist (win (cddr obj))
                           (unless (eq win (car (last obj)))
                             (if (car obj)
                                 (split-window-vertically
                                  (workgroups-window-height win))
                               (split-window-horizontally
                                (workgroups-window-width win))))
                           (inner win))))))
    (let ((f (or frame (selected-frame))))
      (destructuring-bind ((x y w h) idx wtree) config
        (set-frame-position f x y)
        (set-frame-width    f w)
        (set-frame-height   f h)
        (delete-other-windows)
        (inner wtree)
        (set-frame-selected-window
         f (nth idx (workgroups-window-list f)))))))


;;; workgroup restoring

(defun workgroups-restore (workgroup &optional base? frame)
  "Restore WORKGROUP in FRAME or `selected-frame'."
  (workgroups-restore-config
   (if base? (workgroups-base-config workgroup)
     (workgroups-working-config workgroup))
   frame))


;;; mode-line

(defun workgroups-mode-line-update ()
  "Update the mode-line with current workgroup info."
  (setq workgroups-mode-line-string
        (format "[%s]" (workgroups-name (workgroups-current))))
  (force-mode-line-update))

(defun workgroups-mode-line-add ()
  "Turn on workgroups' mode-line display."
  (let ((format mode-line-format)
        (on 'workgroups-mode-line-on))
    (unless (assoc on format)
      (set-default 'mode-line-format
                   (workgroups-list-insert
                    `(,on (" " workgroups-mode-line-string))
                    (1+ (position 'mode-line-position format))
                    format))
      (force-mode-line-update))))

(defun workgroups-mode-line-remove ()
  "Turn off workgroups' mode-line display."
  (let ((elt (assoc 'workgroups-mode-line-on mode-line-format)))
    (when elt
      (set-default 'mode-line-format (remove elt mode-line-format))
      (force-mode-line-update))))


;;; command utils

(defun workgroups-completing-read (&rest args)
  "Call `ido-completing-read' or `completing-read'."
  (apply (if (and (boundp 'ido-mode) ido-mode)
             'ido-completing-read
           'completing-read) args))

(defun workgroups-read-workgroup (&optional noerror)
  "Read a workgroup with `workgroups-completing-read'."
  (workgroups-get-workgroup
   (workgroups-completing-read
    "Workgroup: " (workgroups-names noerror)) noerror))

(defun workgroups-smart-get (&optional workgroup noerror)
  "Return a WORKGROUP, one way or another."
  (or workgroup
      (and current-prefix-arg (workgroups-read-workgroup noerror))
      (workgroups-current noerror)))

(defun workgroups-add-to-kill-ring (config)
  "Add CONFIG to `workgroups-kill-ring'."
  (push config workgroups-kill-ring)
  (let ((wkr workgroups-kill-ring))
    (when (> (length wkr) workgroups-kill-ring-size)
      (setq workgroups-kill-ring (butlast wkr)))))

(defun workgroups-list-swap (w1 w2)
  "Swap current with previous in the workgroups list."
  (when (eq w1 w2) (error "It's pointless to swap %S with itself" name))
  (setq workgroups-list
        (workgroups-swap-util w1 w2 (workgroups-list))))


;;; commands

(defun workgroups-echo-current ()
  "Message name of `workgroups-current'."
  (interactive)
  (message "Current: %S"
           (workgroups-name (workgroups-current))))

(defun workgroups-echo-all ()
  "Display the names of all workgroups in the echo area."
  (interactive)
  (message (mapconcat 'identity (workgroups-names) " | ")))

(defun workgroups-switch (workgroup &optional base?)
  "Switch to workgroup named NAME."
  (interactive (list (workgroups-read-workgroup) current-prefix-arg))
  (let ((name (workgroups-name workgroup))
        (current (workgroups-current t)))
    (when current
      (when (eq workgroup current) (error "Already on %S" name))
      (workgroups-set-working-config current (workgroups-make-config))
      (setq workgroups-previous current))
    (workgroups-restore workgroup base?)
    (setq workgroups-current workgroup)
    (run-hooks 'workgroups-switch-hook)
    (workgroups-mode-line-update)
    (message "Switched to %S." name)))

(defun workgroups-create (name &optional maker-fn)
  "Add workgroup named NAME."
  (interactive "sName: ")
  (when (equal name "") (error "No name specified"))
  (let* ((w (workgroups-get-workgroup name t))
         (wl (workgroups-list t))
         (pos (length wl)))
    (when w
      (unless (yes-or-no-p (format "%S exists. Overwrite? " name))
        (error "Overwriting of %S cancelled" name))
      (setq pos (position w wl))
      (workgroups-delete w))
    (let ((new (if maker-fn (funcall maker-fn)
                 (workgroups-make-default-workgroup name))))
      (workgroups-add new pos)
      (workgroups-switch new)
      (message "Added %S" name))))

(defun workgroups-clone (name &optional workgroup)
  "Create clone of WORKGROUP named NAME.
Add it at the end of `workgroups-list', and switch to it."
  (interactive "sName of clone: ")
  (let ((w (workgroups-smart-get workgroup)))
    (when (workgroups-get-workgroup name t)
      (error "A workgroup named %S already exists" name))
    (let ((new (workgroups-make-current-workgroup name)))
      (workgroups-add new)
      (workgroups-switch new)
      (message "Cloned %S to %S" (workgroups-name w) name))))

(defun workgroups-kill-ring-save ()
  "Copy current config to `workgroups-clipboard'."
  (interactive)
  (workgroups-add-to-kill-ring (workgroups-make-config)))

(defun workgroups-yank ()
  "Restore `workgroups-clipboard' in `selected-frame'."
  (interactive)
  (let ((kr workgroups-kill-ring))
    (unless kr (error "workgroups-kill-ring empty"))
    (let ((wkrp (if (not (eq real-last-command 'workgroups-yank)) 0
                  (mod (1+ workgroups-kill-ring-pos) (length kr)))))
      (setq workgroups-kill-ring-pos wkrp)
      (workgroups-restore-config (nth wkrp kr))
      (message "Yank!"))))

(defun workgroups-kill (&optional workgroup nosave)
  "Kill workgroup named NAME."
  (interactive)
  (let* ((w (workgroups-smart-get workgroup))
         (name (workgroups-name w)))
    (when workgroups-confirm-kill
      (unless (yes-or-no-p (format "Really kill %S?" name))
        (error "Aborted killing %S" name)))
    (unless nosave
      (workgroups-add-to-kill-ring
       (if (eq w (workgroups-current))
           (workgroups-make-config)
         (workgroups-working-config w))))
    (let ((next (workgroups-cnext w (workgroups-list))))
      (workgroups-delete w)
      (if (not (eq w next)) (workgroups-switch next)
        (workgroups-restore-config
         (workgroups-make-default-config))))
    (message "Killed %S." name)))

(defun workgroups-kill-workgroup-and-buffers (&optional workgroup)
  "`workgroups-kill' WORKGROUP and its buffers."
  (interactive)
  (let ((w (workgroups-smart-get workgroup)) bufs)
    (save-window-excursion
      (or (eq w (workgroups-current)) (workgroups-restore w))
      (setq bufs (mapcar 'window-buffer (window-list))))
    (workgroups-kill w)
    (mapc 'kill-buffer bufs)
    (message "Killed %S and its buffer" (workgroups-name w))))

(defun workgroups-delete-other-workgroups ()
  "Delete all but the current workgroup."
  (interactive)
  (let ((w (workgroups-current))
        (wl (workgroups-list)))
    (mapc 'workgroups-delete (remove w wl))
    (message "Deleted all other workgroups")))

(defun workgroups-update (&optional workgroup)
  "Set the base config of WORKGROUP to the current config."
  (interactive)
  (let ((w (workgroups-smart-get workgroup))
        (config (workgroups-make-config)))
    (workgroups-set-base-config    w config)
    (workgroups-set-working-config w config)
    (message "Updated %S" (workgroups-name w))))

(defun workgroups-revert (&optional workgroup)
  "Revert to `workgroups-base-config' of WORKGROUP."
  (interactive)
  (let ((w (workgroups-smart-get workgroup)))
    (workgroups-set-working-config
     w (workgroups-base-config w))
    (when (eq w (workgroups-current))
      (workgroups-restore w t))
    (message "Reverted %S" (workgroups-name w))))

(defun workgroups-jump (&optional n)
  "Switch to the Nth workgroup (zero-indexed) in `workgroups-list'.
Try N, then the prefix arg, then prompt for a number."
  (interactive)
  (let* ((wl (workgroups-list))
         (l  (length wl))
         (n  (or n current-prefix-arg
                 (string-to-number (string last-command-char))
                 (read-from-minibuffer
                  (format "Index [0 - %s]: " (1- l)) nil nil t))))
    (unless (integerp n)
      (error "Argument %s not an integer" n))
    (unless (and (>= n 0) (< n l))
      (error "There are only %s workgroups [0-%s]" l (1- l)))
    (workgroups-switch (nth n wl))))

(defalias 'workgroups-jump-0 'workgroups-jump)
(defalias 'workgroups-jump-9 'workgroups-jump)

(defun workgroups-toggle ()
  "Switch to the previous workgroup."
  (interactive)
  (workgroups-switch (workgroups-previous)))

(defun workgroups-swap ()
  "Swap the current workgroup with the previous."
  (interactive)
  (workgroups-list-swap (workgroups-current) (workgroups-previous))
  (workgroups-echo-all))

(defun workgroups-left (&optional workgroup)
  "Swap WORKGROUP toward the beginning of `workgroups-list'."
  (interactive)
  (let* ((w1 (workgroups-smart-get workgroup))
         (w2 (workgroups-prev-util w1 (workgroups-list))))
    (unless w2
      (error "%S is all the way left" (workgroups-name w1)))
    (workgroups-list-swap w1 w2)
    (workgroups-echo-all)))

(defun workgroups-right (&optional workgroup)
  "Move WORKGROUP toward the end of `workgroups-list'."
  (interactive)
  (let* ((w1 (workgroups-smart-get workgroup))
         (w2 (workgroups-next-util w1 (workgroups-list))))
    (unless w2
      (error "%S is all the way right" (workgroups-name w1)))
    (workgroups-list-swap w1 w2)
    (workgroups-echo-all)))

(defun workgroups-next ()
  "Switch to the next workgroup in `workgroups-list'."
  (interactive)
  (workgroups-switch
   (workgroups-cnext
    (workgroups-current) (workgroups-list))))

(defun workgroups-prev ()
  "Switch to the previous workgroup in `workgroups-list'."
  (interactive)
  (workgroups-switch
   (workgroups-cprev
    (workgroups-current) (workgroups-list))))

(defun workgroups-rename (&optional workgroup)
  "Rename the current workgroup. Prompt for new name."
  (interactive)
  (let* ((w (workgroups-smart-get workgroup))
         (oldname (workgroups-name w))
         (newname (read-from-minibuffer
                   (format "Rename workgroup from %S to: "
                           oldname))))
    (workgroups-set-name w newname)
    (message "Renamed %S to %S." oldname newname)))

(defun workgroups-toggle-mode-line ()
  "Toggle workgroups' mode-line display."
  (interactive)
  (setq workgroups-mode-line-on (not workgroups-mode-line-on))
  (force-mode-line-update)
  (message "mode-line diplay %s"
           (if workgroups-mode-line-on "on" "off")))


;; workgroups-get-by-buffer code

(defun workgroups-get-config-buffers (config)
  "Return the names of all unique buffers in CONFIG."
  (let (bufs)
    (flet ((inner (obj)
                  (if (not (workgroups-window-p obj))
                      (mapc 'inner (cddr obj))
                    (let ((bname (workgroups-wprop :bname obj)))
                      (when (and bname (not (member bname bufs)))
                        (push bname bufs))))))
      (inner config)
      bufs)))

(defun workgroups-get-workgroup-buffers (workgroup)
  "Return the names of all unique buffers in WORKGROUP."
  (let ((bufs (workgroups-get-config-buffers
               (workgroups-working-config workgroup))))
    (dolist (buf (workgroups-get-config-buffers
                  (workgroups-base-config workgroup)) bufs)
      (unless (member buf bufs) (push buf bufs)))))

(defun workgroups-get-buffers ()
  "Return the names of all unique buffers in `workgroups-list'."
  (let (bufs)
    (dolist (w (workgroups-list) bufs)
      (dolist (buf (workgroups-get-workgroup-buffers w))
        (unless (member buf bufs) (push buf bufs))))))

(defun workgroups-get-workgroup-from-buffer (buf)
  "Return the workgroup and config flag that contains BUF."
  (catch 'result
    (dolist (w (workgroups-list))
      (when (member buf (workgroups-get-config-buffers
                         (workgroups-working-config w)))
        (throw 'result (list w)))
      (when (member buf (workgroups-get-config-buffers
                         (workgroups-base-config w)))
        (throw 'result (list w t))))
    (error "No workgroup contains %S" buf)))

(defun workgroups-get-by-buffer ()
  "Switch to the workgroup that contains the specified buffer.
The first workgroup in `workgroups-list' that contains the buffer
is selected."
  (interactive)
  (let ((buf (workgroups-completing-read
              "Buffer: " (workgroups-get-buffers))))
    (destructuring-bind (w &rest base)
        (workgroups-get-workgroup-from-buffer buf)
      (workgroups-switch w base))))


;; file commands

(defun workgroups-save-workgroups (&optional file)
  "Call `workgroups-save-file' on FILE if it's non-nil.
Query for a filename if `current-prefix-arg' is non-nil."
  (interactive)
  (workgroups-set-working-config
   (workgroups-current) (workgroups-make-config))
  (workgroups-save
   (or file (and current-prefix-arg (read-file-name "File: "))))
  (message "Saved %s" workgroups-file))

(defun workgroups-load-workgroups (&optional file)
  "Call `workgroups-load-file' on FILE if it's non-nil.
Query for a filename if `current-prefix-arg' is nil."
  (interactive)
  (workgroups-load
   (or file (and (not current-prefix-arg) (read-file-name "File: "))))
  (when workgroups-autoswitch
    (workgroups-switch (car (workgroups-list))))
  (message "Loaded %s" workgroups-file))


;;; workgroups-map

(defvar workgroups-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-a")    'workgroups-create)
    (define-key map (kbd "C-b")    'workgroups-get-by-buffer)
    (define-key map (kbd "C-c")    'workgroups-clone)
    (define-key map (kbd "C-e")    'workgroups-echo-current)
    (define-key map (kbd "S-C-e")  'workgroups-echo-all)
    (define-key map (kbd "C-f")    'workgroups-load-workgroups)
    (define-key map (kbd "C-l")    'workgroups-right)
    (define-key map (kbd "C-k")    'workgroups-kill)
    (define-key map (kbd "S-C-k")  'workgroups-delete-other-workgroups)
    (define-key map (kbd "C-h")    'workgroups-left)
    (define-key map (kbd "C-m")    'workgroups-toggle-mode-line)
    (define-key map (kbd "C-n")    'workgroups-next)
    (define-key map (kbd "C-p")    'workgroups-prev)
    (define-key map (kbd "C-q")    'workgroups-rename)
    (define-key map (kbd "C-r")    'workgroups-revert)
    (define-key map (kbd "C-s")    'workgroups-save-workgroups)
    (define-key map (kbd "C-t")    'workgroups-toggle)
    (define-key map (kbd "C-u")    'workgroups-update)
    (define-key map (kbd "C-v")    'workgroups-switch)
    (define-key map (kbd "C-w")    'workgroups-kill-workgroup-and-buffers)
    (define-key map (kbd "C-x")    'workgroups-swap)
    (define-key map (kbd "C-y")    'workgroups-yank)
    (define-key map (kbd "M-w")    'workgroups-kill-ring-save)
    (define-key map (kbd "0")      'workgroups-jump-0)
    (define-key map (kbd "1")      'workgroups-jump)
    (define-key map (kbd "2")      'workgroups-jump)
    (define-key map (kbd "3")      'workgroups-jump)
    (define-key map (kbd "4")      'workgroups-jump)
    (define-key map (kbd "5")      'workgroups-jump)
    (define-key map (kbd "6")      'workgroups-jump)
    (define-key map (kbd "7")      'workgroups-jump)
    (define-key map (kbd "8")      'workgroups-jump)
    (define-key map (kbd "9")      'workgroups-jump-9)
    (define-key map (kbd "C-j")    'workgroups-jump)
    (define-key map (kbd "?")      'workgroups-help)
    map)
  "workgroups-mode's keymap.")


;;   \\[elscreen-find-file]  Create new screen and open file
;;   \\[elscreen-display-last-message]    Show last message
;;   \\[elscreen-display-time]    Show time
;;   \\[elscreen-find-file-read-only]  Create new screen and open file but don't allow changes
;;   \\[elscreen-dired]    Create new screen and run dired
;;   \\[elscreen-execute-extended-command]  Read function name, then call it with new screen
;;   \\[elscreen-toggle-display-tab]    Show/hide the tab at the top of screen
;;   \\[elscreen-display-version]    Show ElScreen version


;;; help

(defvar workgroups-help "workgroups keybindings:\n
  \\[workgroups-create]    Create a new workgroup and switch to it
  \\[workgroups-switch]    Switch to a workgroup
  \\[workgroups-get-by-buffer]    Switch to the workgroup and config which contains the specified buffer
  \\[workgroups-clone]    Clone the current workgroup
  \\[workgroups-kill]    Kill a workgroup
  \\[workgroups-kill-workgroup-and-buffers]    Kill a workgroup and its buffer
  \\[workgroups-delete-other-workgroups]    Delete all but the current workgroup
  \\[workgroups-yank]    Restore a killed config to the current workgroup
  \\[workgroups-kill-ring-save]    Save the current config to the kill ring
  \\[workgroups-load-workgroups]    Load a workgroups file
  \\[workgroups-save-workgroups]    Save workgroups to a file
  \\[workgroups-jump]    Jump to a numbered workgroup
  \\[workgroups-jump-0]    Jump to the 0th workgroup
    ...
  \\[workgroups-jump-9]    Jump to the 9th workgroup
  \\[workgroups-revert]    Revert to a workgroup's base config
  \\[workgroups-update]    Set a workgroups base config to its working config
  \\[workgroups-toggle]    Switch to the previously selected workgroup
  \\[workgroups-next]    Switch to the next workgroup circularly
  \\[workgroups-prev]    Switch to the previous workgroup circularly
  \\[workgroups-swap]    Swap the current and previous workgroups
  \\[workgroups-left]    Move a workgroup leftward in workgroups-list
  \\[workgroups-right]    Move a workgroup rightward in workgroups-list
  \\[workgroups-rename]    Rename a workgroup
  \\[workgroups-echo-current]    Display the name of the current workgroup in the echo area
  \\[workgroups-echo-all]    Display the names of all workgroups in the echo area
  \\[workgroups-toggle-mode-line]    Toggle workgroups mode-line display
  \\[workgroups-help]    Show this help message"
  "Help shown by elscreen-help-mode")

(defun workgroups-help ()
  "Show information about workgroups commands."
  (interactive)
  (with-output-to-temp-buffer "*workroups help*"
    (princ (substitute-command-keys workgroups-help))
    (print-help-return-message)))


;;; mode definition

(defun workgroups-query-hook-fn ()
  "Query for save on exit if `workgroups-dirty' is non-nil."
  (and workgroups-dirty
       workgroups-query-save-on-exit
       (y-or-n-p "Workgroups have been modified. Save them? ")
       (workgroups-save))
  t)

(defun workgroups-enable (enable)
  "Enable `workgroups-mode' when ENABLE is t, otherwise disable."
  (cond (enable (add-hook
                 'kill-emacs-query-functions
                 'workgroups-query-hook-fn)
                (when workgroups-default-file
                  (workgroups-load-workgroups workgroups-default-file))
                (workgroups-mode-line-add)
                (setq workgroups-mode t))
        (t      (remove-hook
                 'kill-emacs-query-functions
                 'workgroups-query-hook-fn)
                (workgroups-mode-line-remove)
                (setq workgroups-mode nil))))

;;;###autoload
(define-minor-mode workgroups-mode
  "This toggles workgroups-mode.

If ARG is null, toggle workgroups-mode.
If ARG is a number greater than zero, turn on workgroups-mode.
Otherwise, turn off workgroups-mode."
  :lighter     " wg"
  :init-value  nil
  :global      t
  :group       'workgroups
  (cond (noninteractive   (workgroups-enable nil))
        (workgroups-mode  (workgroups-enable t))
        (t                (workgroups-enable nil))))


;;; provide

(provide 'workgroups-mode)


;;; workgroups-mode.el ends here
