;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; This file is part of Sheeple

;;;; messages.lisp
;;;;
;;;; Message metasheep, message definition and management
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

#+sheeple3.1
(define-bound-variable =standard-message=)
#+sheeple3.1
(defparameter the-std-message-form '(defproto =standard-message= ()
                                     ((name nil :accessor nil)
                                      (lambda-list nil :accessor nil)
                                      (replies nil :accessor nil)
                                      (memo-vector (make-vector 40) :accessor nil)
                                      (arg-info (make-arg-info) :accessor nil))))

#+sheeple3.1
(defun %make-message (&key name lambda-list replies (documentation ""))
  (defsheep (=standard-message=) ((name name) (lambda-list lambda-list)
                                  (replies replies)
                                  (memo-vector (make-vector 40))
                                  (arg-info (make-arg-info)))))

;;;
;;; Message object
;;;
;;; - Messages are the Sheeple equivalent of a generic function. Unlike CLOS' generic functions,
;;;   though, the role messages take is smaller. Messages themselves are fairly blind to the dispatch
;;;   mechanism. As far as the user interface goes, they're used as a sort of interface definition.
;;;   The main role they take on (visible to the user) is to maintain lambda-list congruence across
;;;   different replies (sheeple-speak for methods). Sheeple messages follow the same rules as
;;;   CLOS generic functions use for lambda-list congruence, as outlined in
;;;   http://www.lispworks.com/documentation/HyperSpec/Body/07_fd.htm
;;;
;;;   Design-wise, this is a bit of an annoyance, since it means Replies aren't entirely independent.
;;;   I made the decision many tags ago, though, that maintaining CLOS-style lambda-list congruence
;;;   was worth the price. As it turns out, there were other convenient reasons to have a global
;;;   'registry' of replies: All existing replies can be listed for the user, an obvious interface
;;;   can be defined, and the message object can be used as an obvious place to store the cached
;;;   dispatch information.
(defstruct (message (:constructor %make-message)
                    (:predicate messagep))
  (name nil)
  (lambda-list nil)
  (replies nil)
  (dispatch-cache (make-dispatch-cache))
  (arg-info (make-arg-info)))

;;;
;;; Message definition
;;;

;;; Message table
(defvar *message-table* (make-hash-table :test #'equal)
  "Hashtable for storing message objects. Needs to :test #'equal because
of setf methods, whose names are lists.")

(defun message-table-p (table)
  (hash-table-p table))

(defun find-message (name &optional (errorp t))
  "Finds a message object in `*message-table*', given its `name'.
Raises an error if no message is found, unless `errorp' is set to NIL."
  (or (gethash name *message-table*)
      (when errorp (error 'no-such-message :message-name name))))

(defun (setf find-message) (new-value name)
  (setf (gethash name *message-table*) new-value))

(defun forget-message (name)
  (remhash name *message-table*))

(defun forget-all-messages ()
  (clrhash *message-table*) t)

;;;
;;; Global dispatch cache
;;;
;;; - We hold a global cache for each message, which is filled as different objects are dispatched on.
;;;   This allows fairly quick lookup of applicable replies when a particular message is called over
;;;   and over on the same arguments.
(defparameter *dispatch-cache-size* 40)

(defun make-dispatch-cache ()
  (make-vector *dispatch-cache-size*))

(defun make-dispatch-cache-entry (args replies)
  (cons (make-weak-pointer args) replies))
(defun cache-entry-args (entry)
  (car entry))
(defun cache-entry-replies (entry)
  (cdr entry))

(defun add-entry-to-message (message applicable-replies args index-if-full)
  (let ((dispatch-cache (message-dispatch-cache message))
        (entry (make-dispatch-cache-entry args applicable-replies)))
    (declare (simple-vector dispatch-cache) (fixnum index))
    ;; We first try to make sure a cache is filled up. If it is, we insert the new entry
    ;; into INDEX-IF-FULL. This is a bit leaky, and should probably be improved.
    (aif (position 0 dispatch-cache)
         (setf (svref dispatch-cache it) entry)
         (setf (svref dispatch-cache index-if-full) entry))))

(defun clear-dispatch-cache (message)
  (setf (message-dispatch-cache message) (make-dispatch-cache)))

(defun clear-all-message-caches ()
  (maphash-values 'clear-memo-table *message-table*))

;;;
;;; Arg info
;;; - The stuff in here contains the arg-info object, plus code to handle it.
;;;   Present is also the function that confirms validity of reply lambda-lists,
;;;   and the code that updates the valid arg info for a message whenever a reply
;;;   is added. The add-reply function, though, is in reply-generation.lisp
(defstruct (arg-info (:conc-name nil)
                     (:constructor make-arg-info))
  (arg-info-lambda-list :no-lambda-list)
  arg-info-precedence
  arg-info-metatypes
  arg-info-number-optional
  arg-info-key/rest-p
  arg-info-keys                         ;nil        no &KEY or &REST allowed
                                        ;(k1 k2 ..) Each reply must accept these &KEY arguments.
                                        ;T          must have &KEY or &REST
  msg-info-simple-accessor-type         ; nil, reader, writer, boundp
  (msg-precompute-dfun-and-emf-p nil)   ; set by set-arg-info
  msg-info-static-c-a-m-emf
  (msg-info-c-a-m-emf-std-p t)
  msg-info-fast-mf-p)

(defun arg-info-valid-p (arg-info)
  (numberp (arg-info-number-optional arg-info)))

(defun arg-info-applyp (arg-info)
  (or (plusp (arg-info-number-optional arg-info))
      (arg-info-key/rest-p arg-info)))

(defun arg-info-number-required (arg-info)
  (length (arg-info-metatypes arg-info)))

(defun arg-info-nkeys (arg-info)
  (count-if (fun (not (eq _ t))) (arg-info-metatypes arg-info)))

(defun set-arg-info (msg &key new-reply (lambda-list nil lambda-list-p))
  (let* ((arg-info (message-arg-info msg))
         (replies (message-replies msg))
         (first-p (and new-reply (null (cdr replies)))))
    (when (and (not lambda-list-p) replies)
      (setq lambda-list (message-lambda-list msg)))
    (when (or lambda-list-p
              (and first-p
                   (eq (arg-info-lambda-list arg-info) :no-lambda-list)))
      (multiple-value-bind (nreq nopt keysp restp allow-other-keys-p keywords)
          (analyze-lambda-list lambda-list)
        (when (and replies (not first-p))
          (let ((msg-nreq (arg-info-number-required arg-info))
                (msg-nopt (arg-info-number-optional arg-info))
                (msg-key/rest-p (arg-info-key/rest-p arg-info)))
            (unless (and (= nreq msg-nreq)
                         (= nopt msg-nopt)
                         (eq (or keysp restp) msg-key/rest-p))
              (error 'reply-lambda-list-conflict
                     :lambda-list lambda-list :message msg))))
        (setf (arg-info-lambda-list arg-info)
              (if lambda-list-p
                  lambda-list
                  (create-msg-lambda-list lambda-list)))
        (setf (arg-info-metatypes arg-info) (make-vector nreq))
        (setf (arg-info-number-optional arg-info) nopt)
        (setf (arg-info-key/rest-p arg-info) (not (null (or keysp restp))))
        (setf (arg-info-keys arg-info)
              (if lambda-list-p
                  (if allow-other-keys-p t keywords)
                  (arg-info-key/rest-p arg-info)))))
    (when new-reply
      (check-reply-arg-info msg arg-info new-reply))
    arg-info))

(defun analyze-lambda-list (lambda-list)
  (labels ((make-keyword (symbol)
             (intern (symbol-name symbol)
                     (find-package 'keyword)))
           (parse-key-arg (arg)
             (if (listp arg)
                 (if (listp (car arg))
                     (caar arg)
                     (make-keyword (car arg)))
                 (make-keyword arg))))
    (let ((nrequired 0)
          (noptional 0)
          (keysp nil)
          (restp nil)
          (nrest 0)
          (allow-other-keys-p nil)
          (keywords nil)
          (keyword-parameters nil)
          (state 'required))
      (dolist (x lambda-list)
        (if (memq x lambda-list-keywords)
            (case x
              (&optional         (setq state 'optional))
              (&key              (setq keysp t
                                       state 'key))
              (&allow-other-keys (setq allow-other-keys-p t))
              (&rest             (setq restp t
                                       state 'rest))
              (&aux           (return t))
              (otherwise
               (error "encountered the non-standard lambda list keyword ~S"
                      x)))
            (ecase state
              (required  (incf nrequired))
              (optional  (incf noptional))
              (key       (push (parse-key-arg x) keywords)
                         (push x keyword-parameters))
              (rest      (incf nrest)))))
      (when (and restp (zerop nrest))
        (error "Error in lambda-list:~%~
                After &REST, a DEFMESSAGE lambda-list ~
                must be followed by at least one variable."))
      (values nrequired noptional keysp restp allow-other-keys-p
              (reverse keywords)
              (reverse keyword-parameters)))))

(defun check-reply-arg-info (msg arg-info reply)
  (multiple-value-bind (nreq nopt keysp restp allow-other-keys-p keywords)
      (analyze-lambda-list (reply-lambda-list reply))
    (flet ((lose (string &rest args)
             (error 'sheeple-error
                    :format-control "~@<attempt to add the reply~2I~_~S~I~_~
                                     to the message~2I~_~S;~I~_~
                                     but ~?~:>"
                    :format-args (list reply msg string args)))
           (comparison-description (x y)
             (declare (fixnum x y))
             (if (> x y) "more" "fewer")))
      (let ((msg-nreq (arg-info-number-required arg-info))
            (msg-nopt (arg-info-number-optional arg-info))
            (msg-key/rest-p (arg-info-key/rest-p arg-info))
            (msg-keywords (arg-info-keys arg-info)))
        (unless (= nreq msg-nreq)
          (lose
           "the reply has ~A required arguments than the message."
           (comparison-description nreq msg-nreq)))
        (unless (= nopt msg-nopt)
          (lose
           "the reply has ~A optional arguments than the message."
           (comparison-description nopt msg-nopt)))
        (unless (eq (or keysp restp) msg-key/rest-p)
          (lose
           "the reply and message differ in whether they accept~_~
            &REST or &KEY arguments."))
        (when (consp msg-keywords)
          (unless (or (and restp (not keysp))
                      allow-other-keys-p
                      (every (fun (memq _ keywords)) msg-keywords))
            (lose "the reply does not accept each of the &KEY arguments~2I~_~
                   ~S."
                  msg-keywords)))))))

(defun check-msg-lambda-list (lambda-list)
  (flet ((check-no-defaults (list)
           (awhen (find-if (complement (rcurry 'typep '(or symbol (cons * null)))) list)
             (error 'message-lambda-list-error :arg it :lambda-list lambda-list))))
    (multiple-value-bind (required optional restp rest keyp keys aok auxp)
        (parse-lambda-list lambda-list)
      (declare (ignore required restp rest keyp aok))
      (check-no-defaults optional)
      (check-no-defaults keys)
      (when auxp (error 'message-lambda-list-error :arg '&aux :lambda-list lambda-list)))))

;; Finalizing a message sets the function definition of the message to a
;; lambda that calls the top-level dispatch function on the msg args.
(defun finalize-message (message)
  (let ((name (message-name message)))
    (when (and (fboundp name)
               (not (find-message name nil)))
      (cerror "Replace definition." 'clobbering-function-definition :format-args (list name)))
    (setf (fdefinition name) (curry 'apply-message message))))

;; This handles actual setup of the message object (and finalization)
(defun make-message (&key name lambda-list (documentation ""))
  (let ((message (%make-message :name name :lambda-list lambda-list)))
    (set-arg-info message :lambda-list lambda-list)
    (finalize-message message)
    (setf (documentation message 'message) documentation)
    message))

;; The defmessage macro basically expands to a call to this function (after processing
;; its args, checking lamda-list, etc.)
(defun ensure-message (name &rest all-keys &key lambda-list &allow-other-keys)
  (or (awhen-prog1 (find-message name nil)
        (set-arg-info it :lambda-list lambda-list))
      (setf (find-message name)
            (apply 'make-message :name name :lambda-list lambda-list all-keys))))

;; This is the actual message definition macro.
;; It first verifies that the lambda-list provided is a valid message ll,
;; then expands to a call to ensure-message
;; This pair just pretties up the options during macro expansion
(defun canonize-message-option (option)
  `(',(car option) ',(cadr option)))

(defun canonize-message-options (options)
  (mapcan 'canonize-message-option options))

(defmacro defmessage (name lambda-list &rest options)
  `(progn
     (check-msg-lambda-list ',lambda-list)
     (eval-when (:compile-toplevel :load-toplevel :execute)
       (ensure-message
        ',name
        :lambda-list ',lambda-list
        ,@(canonize-message-options options)))))
