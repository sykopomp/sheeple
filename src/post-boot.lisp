;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; This file is part of Sheeple

;;;; post-boot.lisp
;;;;
;;;; Once sheeple is booted up, we can define messages/replies normally
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

;;;
;;; Object creation protocol
;;;
(defmessage allocate-object (metaobject))
(defreply allocate-object ((metaobject =standard-metaobject=))
  (std-allocate-object metaobject))

(defmessage compute-object-hierarchy-list-using-metaobject (metaobject object))
(defreply compute-object-hierarchy-list-using-metaobject
    ((metaobject =standard-metaobject=) object)
  (std-compute-object-hierarchy-list object))

;;;
;;; Extensible Object Creation
;;;
(defmessage create (proto &key)
  (:documentation "Creates a PROTO. Intended for customization.")
  (:reply ((proto =standard-object=) &rest properties &key) ; FIXME &aok bug
    (object :parents proto :properties (plist-to-wide-alist properties))))

;;;
;;; Printing objects!
;;;

(defmessage print-sheeple-object (object stream)
  (:documentation "Defines the expression print-object uses."))

(defreply print-sheeple-object (object (stream =stream=))
  (std-print-sheeple-object object stream))

(defreply print-sheeple-object ((object =boxed-object=) (stream =stream=))
  (print-unreadable-object (object stream :identity t)
    (format stream "Boxed-object ~:[[~S]~;~S~]"
            (has-direct-property-p object 'nickname)
            (ignore-errors (object-nickname object)))))
