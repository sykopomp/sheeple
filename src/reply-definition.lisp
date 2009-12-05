;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; This file is part of Sheeple

;;;; reply-definition.lisp
;;;;
;;;; Reply and role metasheeple, reply definition and undefinition, role management.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

;;;
;;; Reply objects
;;;
;;; Replies are the Sheeple equivalent of methods. Replies themselves are objects that hold
;;; some basic information about what the reply does, what kind of reply it is, etc.
;;; When reply objects are 'called', their reply-function is fetched directly. By using lambdas,
;;; we're able to latch on to the lexical environment the reply was defined in (so they can be
;;; closures)
(defstruct (reply (:predicate replyp)
                  (:constructor
                   make-reply (message qualifiers lambda-list function
                                       &aux (rank-vector ; This dies if MESSAGE is not a
                                             (make-array ; message -- as it should!
                                              (message-number-required message))))))
  ;; These are set permanently when the reply is created
  (message (error "Must supply a message") :type message :read-only t)
  (qualifiers (error "Must supply qualifiers") :type list :read-only t)
  (lambda-list (error "Must supply lambda-list") :type list :read-only t)
  (function (error "Must supply a function") :type function :read-only t)
  ;; This can be changed dynamically, but must be (or string null) -- clhs documentation
  (documentation nil :type (or string null))
  ;; This is set at creation, and is frobbed in FIND-APPLICABLE-REPLIES
  (rank-vector (error "Bug in Sheeple") :type simple-vector :read-only t))

(define-print-object ((reply reply)) (format t "~S" (reply-name reply)))

;;;
;;; Reply Documentation
;;;

(defmethod documentation ((x reply) (doc-type (eql 't)))
  (reply-documentation x))

(defmethod (setf documentation) (new-value (x reply) (doc-type (eql 't)))
  (setf (reply-documentation x) new-value))

(defun reply-name (reply)
  (message-name (reply-message reply)))

;;;
;;; Roles
;;;
;;; - Roles encapsulate the idea of dispatch. Roles live in object objects themselves and represent
;;;   the basic information about what 'role' that particular object has in dispatching on a
;;;   particular message. As it turns out, all the information roles have to hold is the position
;;;   in which it is supposed to be called, and the actual reply object it's associated with.
;;;   The algorithm takes care of putting everything else together.
(deftype role ()
  '(cons reply fixnum))
(defun rolep (maybe-role)
  (typep maybe-role 'role))

(defun make-role (reply position)
  (cons reply position))

(declaim (ftype (function (role) reply) role-reply)
         (ftype (function (role) fixnum) role-position)
         (inline make-role role-reply role-position))

(defun role-reply (role)
  (car role))
(defun role-position (role)
  (cdr role))

(defun pprint-role (stream role)
  (print-unreadable-object (role stream :identity t)
    (format stream "Role: ~A" (role-name role))))
(set-pprint-dispatch 'role 'pprint-role 1)

(declaim (inline role-message role-name)
         (ftype (function (role) message) role-message))

(defun role-message (role)
  (reply-message (role-reply role)))
(defun role-name (role)
  (reply-name (role-reply role)))

(defun participantp (object reply)
  "Checks if OBJECT is actually involved in dispatching REPLY"
  (when (find-if (curry 'eq reply)
                 (%object-roles object) :key 'role-reply)
    t))

;;;
;;; Reply definition
;;;
(defun ensure-reply (name &key qualifiers lambda-list participants function (documentation ""))
  (let ((message (or (find-message name nil)
                     (warn 'automatic-message-creation :message-name name) ; Returns NIL
                     (ensure-message name :lambda-list (create-msg-lambda-list lambda-list)))))
    (error-when (/= (length participants) (count-required-parameters lambda-list))
                "~&The number of participants conflicts with the lambda list.~@
                 Participants: ~S~%Lambda List: ~S~%" participants lambda-list)
    (%ensure-reply message qualifiers lambda-list participants function documentation)))

(defun %ensure-reply (message qualifiers lambda-list participants function documentation
                      &aux (objectified-participants (objectify-list participants)))
  (aprog1 (make-reply message qualifiers lambda-list function)
    (setf (documentation it 't) documentation) ; same as dox for CLOS methods
    (clear-dispatch-cache message)
    ;; In order to replace existing replies, we must remove them before actually adding them again.
    (remove-specific-reply message qualifiers objectified-participants)
    (add-reply-to-message it message)
    (add-reply-to-objects it objectified-participants)))

(defun add-reply-to-message (reply message)
  (check-reply-arg-info message reply)
  (push reply (message-replies message)))

(defun add-reply-to-objects (reply objects)
  (loop
     for object in objects
     for i from 0
     do (push (make-role reply i)
              (%object-roles object))))

(defun available-replies (object)
  (delete-duplicates
   (append (%object-roles object) (mapcan 'available-replies (object-parents object)))
   :test 'equal))

(defun add-reader-to-object (reader prop-name object)
  (ensure-message reader :lambda-list '(object))
  (ensure-reply reader
                :lambda-list '(object)
                :participants (list object)
                :function (eval (make-reply-lambda reader '(object) ()
                                                   `((property-value object ',prop-name))))))

(defun add-readers-to-object (readers prop-name object)
  (map nil (fun (add-reader-to-object _ prop-name object)) readers)
  object)

(defun add-writer-to-object (writer prop-name object)
  (ensure-message writer :lambda-list '(new-value object))
  (ensure-reply writer
                :lambda-list '(new-value object)
                :participants (list =t= object)
                :function (eval (make-reply-lambda writer '(new-value object) ()
                                                   `((setf (property-value object ',prop-name)
                                                           new-value))))))

(defun add-writers-to-object (writers prop-name object)
  (map nil (fun (add-writer-to-object _ prop-name object)) writers)
  object)

;;;
;;; Reply undefinition
;;;
(defun undefine-reply (name &key qualifiers participants)
  (awhen (find-message name nil)
    (clear-dispatch-cache it)
    (remove-applicable-reply it qualifiers (objectify-list participants))))

(defun remove-specific-reply (message qualifiers participants)
  (let ((reply (find-if (fun (equal qualifiers (reply-qualifiers _)))
                        (find-applicable-replies ;defined in reply-dispatch.lisp
                         message participants nil))))
    (when (and reply
               (every (rcurry 'participantp reply) participants))
      (loop
         for object in participants
         for i from 0
         do (map nil (fun (when (and (eq reply (role-reply _))
                                     (= i (role-position _)))
                            (delete-role _ object)))
                 (%object-roles object)))
      (delete-reply reply))))

(defun remove-applicable-reply (message qualifiers participants)
  (let ((reply (find-if (fun (equal qualifiers (reply-qualifiers _)))
                        (find-applicable-replies
                         message participants nil))))
    (when reply
      (loop
         for object in participants
         for i from 0
         do (map nil (fun (when (and (eq reply (role-reply _))
                                     (= i (role-position _)))
                            (delete-role _ object)))
                 (%object-roles object)))
      (delete-reply reply)
      t)))

(defun delete-reply (reply)
  (deletef (message-replies (reply-message reply)) reply)
  (setf (documentation reply 't) nil))

(defun delete-role (role object)
  (deletef (%object-roles object) role))

;;;
;;; User interface
;;;

;;; Definition
(defmacro defreply (name &rest defreply-args)
  (multiple-value-bind (qualifiers reply-ll docstring body)
      (parse-defreply defreply-args)
    (multiple-value-bind (parameters lambda-list participants required ignorable)
        (parse-specialized-lambda-list reply-ll)
      (declare (ignore parameters required))
      `(progn
         (eval-when (:compile-toplevel :load-toplevel :execute)
           (unless (find-message ',name nil)
             (warn 'automatic-message-creation :message-name ',name))
           (ensure-message ',name :lambda-list ',(create-msg-lambda-list reply-ll)))
         (%ensure-reply (find-message ',name)
                        ',qualifiers
                        ',lambda-list
                        (list ,@participants)
                        ,(make-reply-lambda name lambda-list ignorable body)
                        ,docstring)))))

(defun make-reply-lambda (name lambda-list ignorable body)
  (let* ((msg (find-message name nil))
         (key/restp (when msg (message-key/rest-p msg)))
         (ll (if (and key/restp (not (find '&allow-other-keys lambda-list)))
                 (append lambda-list '(&allow-other-keys))
                 lambda-list)))
    `(lambda (args next-erfun)
       (declare (ignorable next-erfun))
       (flet ((next-reply-p ()
                (not (null next-erfun)))
              (call-next-reply (&rest cnr-args)
                (if (null next-erfun)
                    (error "No next reply")
                    (funcall next-erfun (or cnr-args args)))))
         (declare (ignorable #'next-reply-p #'call-next-reply))
         (block ,(if (listp name) (cadr name) name)
           (destructuring-bind ,ll args
             (declare (ignorable ,@ignorable))
             ,@body))))))

(defun parse-defreply (args)
  (let ((qualifiers nil)
        (lambda-list nil)
        (docstring nil)
        (body nil)
        (parse-state :qualifiers))
    (dolist (arg args)
      (ecase parse-state
        (:qualifiers
         (if (and (atom arg) (not (null arg)))
             (push arg qualifiers)
             (progn (setf lambda-list arg)
                    (setf parse-state :docstring))))
        (:docstring
         (if (stringp arg)
             (setf docstring arg)
             (push arg body))
         (setf parse-state :body))
        (:body (push arg body))))
    (values qualifiers lambda-list docstring (nreverse body))))

;;; Undefinition
(defmacro undefreply (name &rest args)
  (multiple-value-bind (qualifiers specializers)
      (parse-undefreply args)
    `(undefine-reply ',name :qualifiers ',qualifiers
                     :participants `(,,@specializers))))

(defun parse-undefreply (args)
  (let (qualifiers specializers)
    (dolist (arg args (values qualifiers specializers))
      (if (and (atom arg) (not (null arg)))
          (push arg qualifiers)
          (setf specializers arg)))))
