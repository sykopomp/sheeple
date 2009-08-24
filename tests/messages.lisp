;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;;; This file is part of Sheeple

;;;; tests/messages.lisp
;;;;
;;;; Unit tests for messages and replies
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(def-suite messages :in sheeple)

(def-suite reply-combination :in messages)
(in-suite reply-combination)

(defmacro with-flag-stack (&body body)
  (let ((stack (gensym)))
    `(let (,stack)
       (flet ((flag (tag) (push tag ,stack))) ,@body)
       (nreverse ,stack))))

(test reply-stack
  (is (null (with-flag-stack)))
  (is (equal '(1) (with-flag-stack (flag 1))))
  (is (equal '(1 2 3) (with-flag-stack (flag 1) (flag 2) (flag 3)))))

(postboot-test primary
  (defmessage tester (x y))
  (with-sheep-hierarchy ((a) (b a))
    (is (equal '(:a-)
               (with-flag-stack
                 (defreply tester ((x a) y)
                   (flag :a-))
                 (tester a nil))))
    (is (equal '(:b- :a-)
               (with-flag-stack
                 (defreply tester ((x a) y)
                   (flag :a-))
                 (defreply tester ((x b) y)
                   (flag :b-)
                   (call-next-reply))
                 (tester b nil))))))

(def-suite message-definition :in messages)
(in-suite message-definition)

(postboot-test message-object
  (let ((test-message (%make-message :name 'name
                                     :lambda-list 'lambda-list
                                     :replies 'replies
                                     :documentation "dox")))
    (is (message-p test-message))
    (with-accessors ((name          message-name)
                     (lambda-list   message-lambda-list)
                     (replies       message-replies)
                     (memo-vector   message-memo-vector)
                     (arg-info      message-arg-info)
                     (documentation message-documentation))
        test-message
      (is (eq 'name        (message-name test-message)))
      (is (eq 'lambda-list (message-lambda-list test-message)))
      (is (eq 'replies     (message-replies test-message)))
      (is (typep memo-vector '(vector t 40)))
      (is (typep arg-info 'arg-info))
      (is (string= documentation "dox")))))

(test message-table
  (let ((test-message (%make-message :name 'name
                                     :lambda-list 'lambda-list
                                     :replies 'replies
                                     :documentation "dox")))
    (setf (find-message 'name) test-message)
    (is (eq test-message (find-message 'name)))
    (forget-message 'name)
    (is (eq nil (find-message 'name nil)))
    (signals no-such-message (find-message 'name))))

(test finalize-message)
(test ensure-message)
(test defmessage)
(test canonize-message-option)
(test canonize-message-options)
(test check-msg-lambda-list)
(test analyze-lambda-list)

(def-suite reply-definition :in messages)
(in-suite reply-definition)

(test reply-p)
(test role-p)
(test participant-p)
(test ensure-reply)
(test generate-reply)
(test defreply)
(test create-msg-lambda-list)
(test add-reply-to-message)
(test remove-specific-reply)
(test delete-reply)
(test delete-role)
(test add-reply-to-sheeple)
(test undefine-reply)
(test remove-applicable-reply)
(test available-replies)
(test add-readers-to-sheep)
(test add-writers-to-sheep)
(test make-reply-lambda)
(test parse-defreply)
(test extract-var-name)
(test confirm-var-name)
(test undefreply)
(test parse-undefreply)

(def-suite reply-dispatch :in messages)
(in-suite reply-dispatch)

(test primary-reply-p)
(test before-reply-p)
(test after-reply-p)
(test around-reply-p)
(test apply-message)
(test apply-replies)
(test next-reply-p)
(test call-next-reply)
(test compute-effective-reply-function)
(test compute-primary-erfun)
(test find-applicable-replies)
(test %find-applicable-replies)
;; caching
(test create-reply-cache)
(test desired-vector-entry-p)
(test fetch-memo-vector-entry)
(test add-entry-to-message)
(test memoize-reply-dispatch)
;; other dispatch stuff
(test sort-applicable-replies)
(test contain-reply)
(test unbox-replies)
(test fully-specified-p)
(test calculate-rank-score)
(test reply-specialized-portion)
