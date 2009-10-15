;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; conditions.lisp
;;;;
;;;; Holds all special conditions used by Sheeple
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(define-condition sheeple-condition ()
  ((format-control :initarg :format-control :reader sheeple-condition-format-control))
  (:report (lambda (condition stream)
             (format stream (sheeple-condition-format-control condition)))))

(defmacro define-sheeple-condition (name super (&optional string &rest args)
                                    &rest condition-options)
  (let (reader-names)
    `(define-condition ,name ,(ensure-list super)
       ,(loop for arg in args for reader = (intern (format nil "~A-~A" name arg))
           collect
             `(,arg :initarg ,(intern (symbol-name arg) :keyword) :reader ,reader)
           do (push reader reader-names))
       (:report
        (lambda (condition stream)
          (format stream (sheeple-condition-format-control condition)
                  ,@(mapcar #'(lambda (reader) `(,reader condition))
                            (nreverse reader-names)))))
       (:default-initargs :format-control ,string
         ,@(cdr (assoc :default-initargs condition-options)))
       ,@(remove :default-initargs condition-options :key #'car))))

(define-sheeple-condition sheeple-warning (sheeple-condition warning) ())
(define-sheeple-condition sheeple-error (sheeple-condition error) ())

;;; Misc

(define-sheeple-condition topologica-sort-conflict sheeple-error
  ("A conflict arose during a topological sort. There's probably also a bug in
Sheeple, because this condition should always get handled internally.
Current sort status:
  Conflicting elements: ~A
  Sorted elements: ~A
  Conflicting constraints: ~A"
   conflicting-elements sorted-elements constraints))

;;; Molds

(define-sheeple-condition mold-error sheeple-error
  ("An error has occured in Sheeple's backend data structures -- this is a bug ~
    in Sheeple itself."))

(define-sheeple-condition mold-collision mold-error
  ("Can't link ~A, because doing so would conflict with the already-linked ~A."
   new-mold collision-mold))

;;; Objects

(define-sheeple-condition object-hierarchy-error sheeple-error
  ("A circular precedence graph was generated for ~A." object)
  (:documentation "Signaled whenever there is a problem computing the hierarchy list."))

;;; Properties

(define-sheeple-condition object-property-error sheeple-error ()
  (:documentation "Encompasses all that can go wrong with properties."))

(define-sheeple-condition unbound-direct-property object-property-error
  ("Object ~A has no direct property named ~A" object property-name))

(define-sheeple-condition unbound-property object-property-error
  ("Property ~A is unbound for object ~A" property-name object))

;;; Looks like somebody's a long way from home. - Adlai
;;; (define-condition property-locked (sheeple-error) ())

;;; Messages

(define-sheeple-condition clobbering-function-definition sheeple-warning
  ("Clobbering regular function or generic function definition for ~A" function))

(define-sheeple-condition sheeple-message-error sheeple-error ()
  (:documentation "Encompasses all that can go wrong with messages."))

(define-sheeple-condition insufficient-message-args sheeple-message-error
  ("Too few arguments were passed to message ~A" message))

(define-sheeple-condition no-such-message sheeple-message-error
  ("There is no message named ~A" message-name))

(define-sheeple-condition message-lambda-list-error sheeple-message-error
  ("~@<Invalid ~S ~_in the message lambda list ~S~:>" arg lambda-list))

;;; Replies

(define-sheeple-condition sheeple-reply-error sheeple-message-error ()
  (:documentation "Encompasses all that can go wrong with replies."))

(define-sheeple-condition reply-lambda-list-conflict sheeple-reply-error
  ("The lambda list ~S conflicts with that of ~S" lambda-list message))

(define-sheeple-condition no-applicable-replies sheeple-reply-error
  ("No applicable replies for message ~A when called with args:~%~S" message args))

;;; Another lonely leftover. - Adlai
;;; (define-condition no-most-specific-reply (sheeple-error) ())

(define-sheeple-condition no-primary-replies sheeple-reply-error
  ("There are no primary replies for message ~A." message))

(define-condition specialized-lambda-list-error (sheeple-error) ())
