;; This file is part of Sheeple.

;; tests/sheeple.lisp
;;
;; Unit tests for src/sheeple.lisp
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (use-package 'fiveam 'sheeple))

(export 'sheeple-tests)

(def-suite sheeple)
(defun run-all-tests ()
  (run! 'sheeple))
(defmethod asdf:perform ((o asdf:test-op) (c (eql (asdf:find-system :sheeple-tests))))
  (run-all-tests))

(def-suite cloning :in sheeple)

(def-suite clone-general :in cloning)
(in-suite clone-general)
(test equitable-sheep
  "Tests that sheep are correctly identified as equalp.
WARNING: This tests blows the stack if some weird circularity pops up."
  (let ((sheep1 (clone)))
    (is (eql sheep1 sheep1))))

(defclass test-sheep-class (standard-sheep) ())
(test spawn-sheep
  (let ((standard-sheep (clone))
        (test-metaclass-sheep (spawn-sheep nil :metaclass 'test-sheep-class)))
    (is (eql #@dolly (car (sheep-parents (spawn-sheep nil)))))
    (is (eql standard-sheep (car (sheep-parents (spawn-sheep (list standard-sheep))))))
    (is (eql (find-class 'test-sheep-class) (class-of test-metaclass-sheep)))))

(test initialize-sheep
  (is (sheep-p (initialize-sheep (clone))))
  ;; todo - could be more stuff here. Maybe.
  )

(test reinitialize-sheep
  ;; reinitialize-sheep resets the sheep's parents and properties. If :new-parents is
  ;; provided, those parents are used when reinitializing (so #@dolly doesn't end up on the list
  ;; by default)
  (let ((test-sheep (clone))
        (another (clone)))
    (is (eql test-sheep (add-property test-sheep 'var "value" :make-accessors-p nil)))
    (is (has-direct-property-p test-sheep 'var))
    (is (eql test-sheep (add-parent another test-sheep)))
    (is (parentp another test-sheep))
    (is (eql test-sheep (reinitialize-sheep test-sheep)))
    (is (parentp #@dolly test-sheep))
    (is (not (has-direct-property-p test-sheep 'var)))
    (is (not (parentp another test-sheep)))
    (is (eql test-sheep (reinitialize-sheep test-sheep :new-parents (list another))))
    (is (parentp another test-sheep))))

(test clone
  "Basic cloning"
  (is (eql #@dolly (car (sheep-parents (clone)))))
  (let ((obj1 (clone)))
    (is (eql obj1
	     (car (sheep-parents (clone obj1))))))
  (let* ((obj1 (clone))
         (obj2 (clone obj1)))
    (is (eql obj1
	     (car (sheep-parents obj2))))))

(test sheep-nickname
  (let ((sheep (clone)))
    (setf (sheep-nickname sheep) 'test)
    (is (eq 'test (sheep-nickname sheep)))))

(test sheep-documentation
  (let ((sheep (clone)))
    (setf (sheep-documentation sheep) 'test)
    (is (eq 'test (sheep-documentation sheep)))))

(test sheep-parents
  (let* ((grandpa (clone))
         (father (clone grandpa))
         (child (clone father)))
    (is (= 1 (length (sheep-parents father))))
    (is (eql grandpa (car (sheep-parents father))))
    (is (not (member grandpa (sheep-parents child))))
    (is (eql #@dolly (car (sheep-parents grandpa))))))

(test sheep-direct-roles)
(test sheep-hierarchy-list
  (let* ((parent (clone))
         (child (clone parent)))
    (is (member child (sheep-hierarchy-list child)))
    (is (member parent (sheep-hierarchy-list child)))
    (is (member #@dolly (sheep-hierarchy-list child)))
    (is (member #@t (sheep-hierarchy-list child)))))

(test sheep-id
  (let* ((a (clone))
         (b (clone)))
    (is (numberp (sheep-id a)))
    (is (numberp (sheep-id b)))
    (is (= (1+ (sheep-id a)) (sheep-id b)))))

(defclass foo () ())
(test sheep-p
  (let ((sheep (clone))
        (special-sheep (spawn-sheep nil :metaclass 'test-sheep-class)))
    (is (sheep-p sheep))
    (is (sheep-p special-sheep))
    (is (not (sheep-p (make-instance 'foo))))
    (is (not (sheep-p "foo")))
    (is (not (sheep-p 5)))))

(test copy-sheep ;; this isn't even written properly yet
  ) 
(test add-parent
  (let ((obj1 (clone))
        (obj2 (clone)))
    (is (eql #@dolly (car (sheep-parents obj1))))
    (is (eql #@dolly (car (sheep-parents obj2))))
    (is (eql obj1 (add-parent obj2 obj1)))
    (is (eql obj2 (car (sheep-parents obj1))))))

(test add-parents
  (let ((parent1 (clone))
        (parent2 (clone))
        (parent3 (clone))
        (child (clone)))
    (setf (sheep-nickname parent1) 'parent1)
    (setf (sheep-nickname parent2) 'parent2)
    (setf (sheep-nickname parent3) 'parent3)
    (is (eql child (add-parents (list parent1 parent2 parent3) child)))
    (is (equal (list parent1 parent2 parent3 #@dolly)
               (sheep-parents child)))))

(test remove-parent
  (let* ((p1 (clone))
         (p2 (clone))
         (child (clone p1 p2)))
    (is (equal (list p1 p2) (sheep-parents child)))
    (is (eql child (remove-parent p1 child)))
    (is (equal (list p2) (sheep-parents child)))))

(test allocate-sheep
  (is (sheep-p (allocate-sheep)))
  (is (sheep-p (allocate-sheep 'test-sheep-class))))

(def-suite inheritance :in cloning)
(in-suite inheritance)
(test parentp
  (let* ((grandpa (clone))
         (father (clone grandpa))
         (child (clone father)))
    (is (parentp grandpa father))
    (is (parentp father child))
    (is (not (parentp child father)))
    (is (not (parentp grandpa child)))))

(test childp
  (let* ((grandpa (clone))
         (father (clone grandpa))
         (child (clone father)))
    (is (childp child father))
    (is (childp father grandpa))
    (is (not (childp grandpa father)))
    (is (not (childp father child)))))

(test ancestorp
  (let* ((grandpa (clone))
         (father (clone grandpa))
         (child (clone father)))
    (is (ancestorp grandpa father))
    (is (ancestorp grandpa child))
    (is (ancestorp father child))
    (is (not (ancestorp child grandpa)))
    (is (not (ancestorp child father)))
    (is (not (ancestorp father grandpa)))))

(test descendantp
  (let* ((grandpa (clone))
         (father (clone grandpa))
         (child (clone father)))
    (is (descendantp father grandpa))
    (is (descendantp child grandpa))
    (is (descendantp child father))
    (is (not (descendantp grandpa child)))
    (is (not (descendantp father child)))
    (is (not (descendantp grandpa father)))))

(test collect-parents
  (let ((sheep (clone)))
   (is (equal (list #@t #@dolly sheep) (collect-parents sheep)))))

(test compute-sheep-hierarchy-list
  (let* ((parent (clone))
         (child (clone parent)))
    (is (equal (list child parent #@dolly #@t)
               (compute-sheep-hierarchy-list child)))))

;;;
;;; DEFCLONE
;;;
(def-suite defclone :in cloning)
(in-suite defclone)

;;; macro processing
(test canonize-sheeple
  (is (equal '(list foo bar baz) (canonize-sheeple '(foo bar baz)))))

(test canonize-property
  (is (equal '(list 'VAR "value") (canonize-property '(var "value"))))
  (is (equal '(list 'VAR "value" :readers '(var) :writers '((setf var)))
             (canonize-property '(var "value") t)))
  (is (equal '(list 'VAR "value" :writers '((setf var)))
             (canonize-property '(var "value" :reader nil) t)))
  (is (equal '(list 'VAR "value" :readers '(var))
             (canonize-property '(var "value" :writer nil) t)))
  (is (equal '(list 'VAR "value")
             (canonize-property '(var "value" :accessor nil) t))))

(test canonize-properties
  (is (equal '(list (list 'VAR "value")) (canonize-properties '((var "value"))))))

(test canonize-clone-options
  (is (equal '(:metaclass 'foo :other-option 'bar)
             (canonize-clone-options '((:metaclass 'foo) (:other-option 'bar))))))

(test defclone
  (let* ((parent (clone))
         (test-sheep (defclone (parent) ((var "value")))))
    (is (sheep-p test-sheep))
    (is (parentp parent test-sheep))
    (is (has-direct-property-p test-sheep 'var))
    ;; todo - this should also check that reader/writer/accessor combinations are properly added
    ))
