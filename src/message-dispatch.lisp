;; This file is part of Sheeple

;; message-dispatch.lisp
;;
;; Message execution and dispatch
;;
;; TODO
;; * memoize message dispatch
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(defun primary-message-p (message)
  (null (message-qualifiers message)))

(defun before-message-p (message)
  (when (member :before (message-qualifiers message))
    t))

(defun after-message-p (message)
  (when (member :after (message-qualifiers message))
    t))

(defun around-message-p (message)
  (when (member :around (message-qualifiers message))
    t))

(defun apply-buzzword (buzzword args)
  (let* ((relevant-args-length (arg-info-number-required (buzzword-arg-info buzzword)))
	 (messages (find-applicable-messages buzzword
					     (subseq args 0 relevant-args-length))))
    (apply-messages messages args)))

(defstruct cache
  name
  around
  primary
  before
  after
  messages)

(defun apply-messages (cache args)
  (let ((messages (cache-messages cache))
	(around (cache-around cache))
	(primaries (cache-primary cache)))
    (when (null primaries)
      (let ((name (cache-name cache)))
	(error 'no-primary-messages
	       :format-control 
	       "There are no primary messages for buzzword ~A When called with args:~%~S"
	       :format-args (list name args))))
    (if around
	(apply-message (car around) args (remove around messages))
    	(let ((befores (cache-before cache))
	      (afters (cache-after cache)))
	  (when befores
	    (dolist (before befores)
	      (apply-message before args nil)))
	  (multiple-value-prog1
	      (apply-message (car primaries) args (cdr primaries))
	    (when afters
	      (dolist (after (reverse afters))
		(apply-message after args nil))))))))

(defun create-message-cache (buzzword messages)
  (make-cache
   :name (buzzword-name buzzword)
   :messages messages
   :primary (remove-if-not #'primary-message-p messages)
   :around (remove-if-not #'around-message-p messages)
   :before (remove-if-not #'before-message-p messages)
   :after (remove-if-not #'after-message-p messages)))

(defun apply-message (message args next-messages)
  (let ((function (message-function message)))
    (funcall function args next-messages)))

(defun find-applicable-messages (buzzword args &key (errorp t))
  (multiple-value-bind (msg-cache has-p)
      (gethash args (buzzword-memo-table buzzword))
    (if has-p
	msg-cache
	(let ((new-msg-list (%find-applicable-messages buzzword args :errorp errorp)))
	  (memoize-message-dispatch buzzword args new-msg-list)))))

(defun memoize-message-dispatch (buzzword args msg-list)
  (setf (gethash args (buzzword-memo-table buzzword)) (create-message-cache buzzword msg-list)))

(defun %find-applicable-messages  (buzzword args &key (errorp t))
  "Returns the most specific message using SELECTOR and ARGS."
  (let ((selector (buzzword-name buzzword))
	(n (length args))
	(discovered-messages nil)
	(contained-applicable-messages nil))
    (loop 
       for arg in args
       for index upto (1- n)
       do (let* ((arg (if (sheep-p arg)
			  arg
			  (sheepify arg)))
		 (curr-sheep-list (sheep-hierarchy-list arg)))
	    (loop
	       for curr-sheep in curr-sheep-list
	       for hierarchy-position upto (1- (length curr-sheep-list))
	       do (dolist (role (sheep-direct-roles curr-sheep))
		    (when (and (equal selector (role-name role)) ;(eql buzzword (role-buzzword role))
			       (= index (role-position role)))
		      (let ((curr-message (role-message-pointer role)))
			(when (= n (length (message-specialized-portion curr-message)))
			  (when (not (member curr-message
					     discovered-messages
					     :key #'message-container-message))
			    (pushnew (contain-message curr-message) discovered-messages))
			  (let ((contained-message (find curr-message
							 discovered-messages
							 :key #'message-container-message)))
			    (setf (elt (message-container-rank contained-message) index) 
				  hierarchy-position)
			    (when (fully-specified-p (message-container-rank contained-message))
			      (pushnew contained-message contained-applicable-messages :test #'equalp))))))))))
    (if contained-applicable-messages
	(unbox-messages (sort-applicable-messages contained-applicable-messages))
	(when errorp
	  (error 'no-applicable-messages
		 :format-control
		 "There are no applicable messages for buzzword ~A when called with args:~%~S"
		 :format-args (list selector args))))))

(defun unbox-messages (messages)
  (mapcar #'message-container-message messages))

(defun sort-applicable-messages (message-list &key (rank-key #'<))
  (sort message-list rank-key
	:key (lambda (contained-message)
	       (calculate-rank-score (message-container-rank contained-message)))))

(defun contain-message (message)
  (make-message-container
   :message message
   :rank (make-array (length (message-specialized-portion message))
		     :initial-element nil)))

(defstruct message-container
  message
  rank)

(defun fully-specified-p (rank)
  (loop for item across rank
     do (when (eql item nil)
	  (return-from fully-specified-p nil)))
  t)

(defun calculate-rank-score (rank)
  (let ((total 0))
    (loop for item across rank
       do (when (numberp item)
	    (incf total item)))
    total))

(defun message-specialized-portion (msg)
  (parse-lambda-list (message-lambda-list msg)))