;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; This file is part of Sheeple

;;;; post-boot.lisp
;;;;
;;;; Once sheeple is booted up, we can define messages/replies normally
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

;;;
;;; Sheep creation protocol
;;;
(defmessage allocate-sheep (metasheep))
(defreply allocate-sheep ((metasheep =standard-metasheep=))
  (std-allocate-sheep metasheep))

(defmessage compute-sheep-hierarchy-list-using-metasheep (metasheep sheep))
(defreply compute-sheep-hierarchy-list-using-metasheep
    ((metasheep =standard-metasheep=) sheep)
  (std-compute-sheep-hierarchy-list sheep))

(defmessage finalize-sheep-inheritance-using-metasheep (metasheep sheep))
(defreply finalize-sheep-inheritance-using-metasheep
    ((metasheep =standard-metasheep=) sheep)
  (std-finalize-sheep-inheritance sheep))

(defmessage remove-parent-using-metasheeple (parent-metasheep child-metasheep parent child))
(defreply remove-parent-using-metasheeple ((parent-metasheep =standard-metasheep=)
                                           (child-metasheep =standard-metasheep=)
                                           parent child)
  (std-remove-parent parent child))

(defmessage add-parent-using-metasheeple (parent-metasheep child-metasheep parent child))
(defreply add-parent-using-metasheeple ((parent-metasheep =standard-metasheep=)
                                        (child-metasheep =standard-metasheep=)
                                        parent child)
  (std-add-parent parent child))

;;;
;;; Nicknames
;;;
(defun sheep-nickname (sheep)
  "Returns SHEEP's nickname"
  (property-value sheep 'nickname))

(defun (setf sheep-nickname) (new-nickname sheep)
  "Sets SHEEP's nickname to NEW-NICKNAME"
  (handler-bind ((unbound-property 'continue))
    (setf (property-value sheep 'nickname) new-nickname)))

;;; Now we name all the built-in sheep like we're Adam in Eden.
(mapc #'(setf sheep-nickname)
      '(=t= =standard-sheep= =standard-metasheep= =boxed-object= =symbol=
        =sequence= =array= =number= =character= =function= =hash-table=
        =package= =pathname= =readtable= =stream= =list= =null= =cons=
        =vector= =bit-vector= =string= =complex= =integer= =float=)
      (list =t= =standard-sheep= =standard-metasheep= =boxed-object= =symbol=
            =sequence= =array= =number= =character= =function= =hash-table=
            =package= =pathname= =readtable= =stream= =list= =null= =cons=
            =vector= =bit-vector= =string= =complex= =integer= =float=))

;;;
;;; Sheep Documentation
;;;

(defmethod documentation ((x sheep) (doc-type (eql 't)))
  (property-value x 'documentation))

(defmethod (setf documentation) (new-value (x sheep) (doc-type (eql 't)))
  (handler-bind ((unbound-property 'continue))
    (setf (property-value x 'documentation) new-value)))

;;;
;;; Printing sheep!
;;;

(defmessage print-sheep (sheep stream)
  (:documentation "Defines the expression print-object uses."))

(defreply print-sheep (sheep (stream =stream=))
  (std-print-sheep sheep stream))

(defreply print-sheep ((sheep =boxed-object=) (stream =stream=))
  (print-unreadable-object (sheep stream :identity t)
    (format stream "Boxed-object ~:[[~S]~;~S~]"
            (has-direct-property-p sheep :nickname)
            (ignore-errors (sheep-nickname sheep)))))
