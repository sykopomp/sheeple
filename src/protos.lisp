;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-
;;;;
;;;; This file is part of Sheeple
;;;;
;;;; protos.lisp
;;;;
;;;; Infrastructure For Global Prototype Objects
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :sheeple)

;;; Originally, the `defproto' macro declared the new proto's name globally
;;; special,and placed (or reinitialized) the proto in the new variable's value
;;; cell. The following quote from http://redmine.sykosomatic.org/issues/show/6
;;; explains why this is unsatisfactory:
;;;
;;;     The DEFPROTO form is currently a big blocker for making Sheeple
;;;   multi-threading-capable. Using dynamic variables means that DEFPROTO forms
;;;   evaluated in one thread will not become available to other threads. It
;;;   also means that there are some very undefined semantics when the proto's
;;;   symbol is shadowed.
;;;
;;; The new system is a hybrid between a common hack known as "global lexicals",
;;; and a prototype namespace which existed in older versions of Sheeple. In old
;;; versions, prototypes were stored in a separate namespace, accessible through
;;; the accessor function `proto'. This system kinda sucked, because it involed
;;; a readmacro for expanding #@foo to (proto 'foo).
;;;
;;; In the new system, we go back to a separate namespace for prototype objects,
;;; but we add symbol macro support, so that proto names can be used just like
;;; global lexical variables. Eventually, this system can also be made blazingly
;;; efficient through judicious use of LOAD-TIME-VALUE and friends.

(defvar *prototype-objects* (make-weak-hash-table :test #'eq :weakness :key)
  "A mapping from symbols to the prototype objects which they designate")

(defun proto (name &optional (errorp t))
  (check-type name symbol)
  (multiple-value-bind (proto foundp)
      (gethash name *prototype-objects*)
    (when (and (not foundp) errorp)
      ;; FIXME: Needs a proper condition class
      (error "No prototype object named ~S" name))
    proto))

(defun (setf proto) (new-proto name &optional errorp)
  (declare (ignore errorp))
  (check-type name symbol)
  (check-type new-proto object)
  (setf (gethash name *prototype-objects*) new-proto))

(defmacro define-proto-name (name)
  (check-type name symbol)
  `(define-symbol-macro ,name (proto ',name)))

;;;
;;; Backend Bootstrap
;;;

(define-proto-name =standard-metaobject=)

(setf =standard-metaobject= (%make-empty-object)
      (%object-lineage =standard-metaobject=)
      (make-lineage =standard-metaobject= () ()))
