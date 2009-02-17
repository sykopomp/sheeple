;; This file is part of Sheeple

;; tests/buzzwords.lisp
;;
;; Unit tests for src/buzzwords.lisp
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeplette-tests)

(def-suite buzzword-tests :in sheeplette)

(in-suite buzzword-tests)

(test buzzword-definition
  "Checks basic buzzword definition, confirms that FIND-BUZZWORD 
errors when a buzzword doesn't exist."
  (defbuzzword test-buzz (:documentation "This is a test"))
  (is (buzzword-p (find-buzzword 'test-buzz)))
  (signals no-such-buzzword (find-buzzword 'another-buzzword))
  (undefbuzzword test-buzz)
  (defun test-buzz () (print "durr hurr"))
  (signals sheeplette::clobbering-function-definition (defbuzzword test-buzz
							  (:documentation "OHNOES")))
  (fmakunbound 'test-buzz))

(test buzzword-undefinition
  "Usage of the undefbuzzword macro, confirmation of removal of all messages and
relevant role objects from the system."
  (defbuzzword test-buzz)
  (undefbuzzword test-buzz)
  (signals no-such-buzzword (find-buzzword 'test-buzz))
  (signals undefined-function (test-buzz))
  (is (not (sheeplette::participant-p =dolly= 'test-buzz)))
  (defmessage another-buzzer (foo) foo)
  (defmessage another-buzzer ((foo =string=)) (declare (ignore foo)) "String returned!")
  (undefmessage another-buzzer ((foo =string=)))
  (is (equal "hei-ho!" (another-buzzer "hei-ho!")))
  (undefmessage another-buzzer (foo))
  (signals sheeplette::no-applicable-messages (another-buzzer =dolly=)) ; this package bs pisses me off
  (is (not (sheeplette::participant-p =dolly= 'test-buzz)))
  (is (not (sheeplette::participant-p =string= 'test-buzz)))
  (undefbuzzword another-buzzer)
  (signals no-such-buzzword (find-buzzword 'another-buzzer))
  (signals undefined-function (another-buzzer "WHAT ARE YOU GONNA DO, BLEED ON ME?!")))

(test message-undefinition
  "Tests undefmessage macro."
  (defbuzzword foo)
  (defmessage foo (foo) foo)
  (is (equal =dolly= (foo =dolly=)))
  (undefmessage foo (foo))
  (signals sheeplette::no-applicable-messages (foo =dolly=))
  (defmessage foo ((string =string=) (another =string=)) (concatenate 'string string another))
  (is (equal "fullstring" (foo "full" "string")))
  (undefmessage foo ((x =string=) (y =string=)))
  (signals sheeplette::no-applicable-messages (foo "full" "string"))
  (undefbuzzword foo))

(test basic-message-definition
  "Checks that messages are defined properly, and added to their respective objects.
also, checks that a style-warning is signaled if there is no buzzword defined."
  (undefbuzzword test-message)
  (signals style-warning (defmessage test-message (foo) (print foo)))
  (defbuzzword test-message)
  (defmessage test-message (foo) (print foo))
  (is (buzzword-p (find-buzzword 'test-message)))
  (is (member 'test-message (available-messages =dolly=)))
  (is (message-p (car (buzzword-messages (find-buzzword 'test-message)))))
  (undefbuzzword test-message))

(test multimessage-definition
  "Checks that multimessages are defined correctly, with roles added
to their respective participants, with correct role-indexes, etc."
  (defmessage test-message (foo bar) bar foo)
  (let ((sheep1 (clone () () (:nickname "sheep1")))
	(sheep2 (clone () () (:nickname "sheep2"))))
    (defmessage test-message ((foo sheep1) (bar sheep2)) foo bar)
    (is (eql t (sheeplette::participant-p sheep1 'test-message)))
    (is (eql t (sheeplette::participant-p sheep2 'test-message)))
    (is (member 'test-message (available-messages sheep1)))
    (is (member 'test-message (available-messages sheep2)))
    (let ((sheep1-roles (sheep-direct-roles sheep1))
	  (sheep2-roles (sheep-direct-roles sheep2)))
      (is (= 0 (role-position (car sheep1-roles))))
      (is (= 1 (role-position (car sheep2-roles))))))
  (undefbuzzword test-message))

(test message-redefinition
  "Confirms correct redefinition of messages"
  (defbuzzword synergize)
  (defmessage synergize ((x =number=) (y =number=)) (+ x y))
  (is (= 10 (synergize 6 4)))
  (defmessage synergize ((y =number=) (x =number=)) (* x y))
  (is (= 24 (synergize 6 4)))
  (undefbuzzword synergize))

(test basic-message-dispatch
  "Checks that basic single-dispatch messages work."
  (let ((test-sheep (clone () () (:nickname "testie")))
	(another-sheep (clone () () (:nickname "rejected-failure"))))
    (defmessage test-message ((sheep test-sheep)) (sheep-nickname sheep))
    (is (equal "testie" (test-message test-sheep)))
    (signals sheeplette::no-applicable-messages (test-message another-sheep)))
  (undefbuzzword test-message))

(test before-messages
  "Checks proper dispatch of :before messages."
  (let ((test-sheep (clone () ((var "value")))))
    (defmessage get-var ((sheep test-sheep))
      (property-value sheep 'var))
    (is (equal "value" (get-var test-sheep)))
    (defmessage get-var :before ((sheep test-sheep))
		(setf (property-value sheep 'var) "new-value"))
    (is (equal "value" (property-value test-sheep 'var)))
    (is (equal "new-value" (get-var test-sheep)))
    (setf (property-value test-sheep 'var) "different-value")
    (is (equal "different-value" (property-value test-sheep 'var)))
    (is (equal "new-value" (get-var test-sheep)))
    (undefbuzzword get-var)))

(test after-messages
  "Checks proper dispatch of :after messages."
  (let ((test-sheep (clone () ((var "value")))))
    (defmessage get-var ((sheep test-sheep))
      (property-value sheep 'var))
    (is (equal "value" (get-var test-sheep)))
    (defmessage get-var :after ((sheep test-sheep))
		(setf (property-value sheep 'var) "new-value"))
    (is (equal "value" (get-var test-sheep)))
    (is (equal "new-value" (property-value test-sheep 'var)))
    (setf (property-value test-sheep 'var) "different-value")
    (is (equal "different-value" (get-var test-sheep)))
    (is (equal "new-value" (property-value test-sheep 'var)))
    (undefbuzzword get-var)))

(test around-messages
  "Checks proper dispatch of :around messages."
  (let ((test-sheep (clone () ((var "value")))))
    (defmessage get-var ((sheep test-sheep))
      (property-value sheep 'var))
    (is (equal "value" (get-var test-sheep)))
    (defmessage get-var :around ((sheep test-sheep))
		(concatenate 'string "a " (call-next-message)))
    (is (equal "a value" (get-var test-sheep)))
    (is (equal "value" (property-value test-sheep 'var)))
    (setf (property-value test-sheep 'var) "different-value")
    (is (equal "different-value" (property-value test-sheep 'var)))
    (is (equal "a different-value"  (get-var test-sheep)))
    (is (equal "different-value" (property-value test-sheep 'var)))
    (undefbuzzword get-var)))

(test call-next-message
  "Tests proper dispatch of next-message on a call to (call-next-message)"
  (let ((test-sheep (clone () ((var "value")))))
    (defmessage get-var (something) (property-value something 'var))
    (is (equal "value" (get-var test-sheep)))
    (defmessage get-var ((sheep test-sheep)) (call-next-message))
    (is (equal "value" (get-var test-sheep)))
    (undefbuzzword get-var)))

(test next-message-p
  "Checks that next-message-p returns T or NIL when appropriate."
  (let ((test-sheep (clone () ((var "value")))))
    (defmessage get-var (something) (property-value something 'var))
    (is (equal "value" (get-var test-sheep)))
    (defmessage get-var ((sheep test-sheep)) (next-message-p))
    (is (equal t (get-var test-sheep)))
    (undefbuzzword get-var)
    (defmessage get-var ((sheep test-sheep)) (next-message-p))
    (is (equal nil (get-var test-sheep)))
    (undefbuzzword get-var)))

(test multimessage-dispatch
  ;; TODO
  "Checks correct multimethod dispatching."
  (defmessage foo ((foo =number=))
    foo)
  (defmessage foo ((foo =number=) (bar =number=))
    (+ foo bar))
  (defmessage foo (foo bar)
    foo bar)
  (is (= 5 (foo 2 3)))
  (is (= 5 (foo 5)))
  (is (equal "bar" (foo "foo" "bar")))
  (signals sheeplette::no-applicable-messages (foo 1 2 3))
  (undefbuzzword foo)
  (let* ((sheep1 (clone () () (:nickname "sheep1")))
	 (sheep2 (clone (sheep1) () (:nickname "sheep2")))
	 (sheep3 (clone (sheep1) () (:nickname "sheep3")))
	 (sheep4 (clone (sheep2) () (:nickname "sheep4")))
	 (sheep5 (clone (sheep4 sheep3) () (:nickname "sheep5"))))
    (defmessage foo ((foo sheep1) (bar sheep1)) 
      (declare (ignore foo bar))
      (print "sheep1 x2"))
    (defmessage foo ((foo sheep2) (bar sheep2))
      (declare (ignore foo bar))
      (print "sheep2 x2"))
    (is (equal "sheep1 x2" (foo sheep1 sheep1)))
    (is (equal "sheep2 x2" (foo sheep2 sheep2)))
    (is (equal "sheep1 x2" (foo sheep3 sheep3)))
    (is (equal "sheep1 x2" (foo sheep3 sheep4)))
    (is (equal "sheep1 x2" (foo sheep5 sheep1)))
    (is (equal "sheep2 x2" (foo sheep5 sheep2)))
    (defmessage foo ((foo sheep1) (bar sheep2))
      (declare (ignore foo bar))
      (print "sheep1,2"))
    (defmessage foo ((foo sheep2) (bar sheep1))
      (declare (ignore foo bar))
      (print "sheep2,1"))
    (is (equal "sheep1,2" (foo sheep1 sheep2)))
    (is (equal "sheep2,1" (foo sheep2 sheep1)))
    ;; I don't even know how to test the advanced dispatch stuff...
    ))

;;; TODO
;; (test full-method-combination
;;   "Checks that various method combinations work properly."
;; )
