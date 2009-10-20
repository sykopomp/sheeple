;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;;
;;;; This file is part of Sheeple.

;;;; tests/objects.lisp
;;;;
;;;; Unit tests for src/objects.lisp
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(def-fixture with-std-object ()
  (let ((object (std-allocate-object =standard-metaobject=)))
    (&body)))

(def-fixture allocate-object (metaobject)
  (let ((object (allocate-object metaobject)))
    (&body)))

(def-suite objects :in sheeple)
;;;
;;; Allocation
;;;
;;; new structure for sheep objects:
;;; #(mold metaobject properties-values roles)
;;; mold := pointer to the appropriate mold for this object
;;; metaobject := pointer to the appropriate metaobject
;;; property-values := vector of direct property values
;;; roles := proper list of direct roles
(def-suite creation :in objects)
(def-suite allocation :in creation)

(def-suite std-allocate-object :in allocation)
(in-suite std-allocate-object)

(test (std-object-basic-structure :fixture with-std-object)
  (is (typep object 'structure-object))
  (is (typep object 'object)))

(test std-object-initial-values
  (let ((object (std-allocate-object =standard-metaobject=)))
    (is (eq =standard-metaobject= (%object-metaobject object)))
    (is (eq (ensure-mold nil #())  (%object-mold object)))
    (is (null (%object-property-values object)))
    (is (null (%object-roles object)))))

#+nil
(test allocate-object
  (let ((object (allocate-object =standard-metaobject=)))
    (is (eq =standard-metaobject= (%object-metaobject object)))
    (is (eq nil (%object-parents object)))
    (is (eq nil (%object-properties object)))
    (is (eq nil (%object-roles object)))
    (is (eq nil (%object-hierarchy-cache object)))
    (is (eq nil (%object-children object)))))

(in-suite allocation)

(test std-object-p
  (for-all ((object (fun (std-allocate-object (funcall (gen-integer))))))
    (is (not (std-object-p object))))
  (for-all ((object (fun (std-allocate-object =standard-metaobject=))))
    (is (std-object-p object))))

(test (objectp :fixture (allocate-object =standard-metaobject=))
  (is (objectp object)))

(test (equality-basic :fixture with-std-object)
  (is (eq object object))
  (is (eql object object))
  (5am:finishes                         ; Does the heap blow up?
    (equal object object)
    (equalp object object)))

(def-suite low-level-accessors :in objects)
(in-suite low-level-accessors)

(test (%object-metaobject :fixture with-std-object)
  (is (eql =standard-metaobject= (%object-metaobject object)))
  (is (null (setf (%object-metaobject object) nil)))
  (is (null (%object-metaobject object))))

(test (%object-mold :fixture with-std-object)
  (is (eq (ensure-mold nil #()) (%object-mold object)))
  (let ((mold (ensure-mold nil #(nickname))))
    (is (eq mold (setf (%object-mold object) mold)))
    (is (eq mold (%object-mold object)))))

(test (%object-property-values :fixture with-std-object)
  (is (null (%object-property-values object)))
  (is (equal 'test (setf (%object-property-values object) 'test)))
  (is (equal 'test (%object-property-values object))))

(test (%object-roles :fixture with-std-object)
  (is (null (%object-roles object)))
  (is (equal '(foo) (setf (%object-roles object) '(foo))))
  (is (equal '(foo) (%object-roles object))))

(def-suite interface-accessors :in objects)
(in-suite interface-accessors)

(test (object-metaobject :fixture with-std-object)
  (is (eql =standard-metaobject= (object-metaobject object)))
  (is (null (fboundp '(setf object-metaobject)))))

(def-suite inheritance :in objects)
(def-suite inheritance-basic :in inheritance)
(in-suite inheritance-basic)

(test collect-ancestors
  (with-object-hierarchy (a (b a) (c b))
    (is (find b (collect-ancestors c)))
    (is (find a (collect-ancestors b)))
    (is (find a (collect-ancestors c)))
    (is (not (find c (collect-ancestors c))))
    (is (not (find c (collect-ancestors b))))))

(test local-precedence-ordering
  (with-object-hierarchy (a b c (d a b c))
    (is (equal (acons d a (acons a b (acons b c nil)))
               (local-precedence-ordering d)))))

;;; I'm gonna stop pretending as though I have a clue
;;; how to test what this actually SHOULD do
(test std-tie-breaker-rule)

(test object-hierarchy-list
  (with-object-hierarchy (parent (child parent))
    (is (equal (list child parent =standard-object= =t=)
               (object-hierarchy-list child))))
  (with-object-hierarchy (a (b a) (c b))
    (is (equal (list c b a =standard-object= =t=)
               (object-hierarchy-list c))))
  (with-object-hierarchy (a b (c a) (d a) (e b c) (f d) (g c f) (h g e))
    (is (equal (list h g e b c f d a =standard-object= =t=)
               (object-hierarchy-list h)))))

;;; Testing the utility...
(in-suite objects)
(test with-object-hierarchy
  (with-object-hierarchy (a (b a) (c a) (d b c))
    (is (eq =standard-object= (car (object-parents a))))
    (is (eq a (car (object-parents b))))
    (is (eq a (car (object-parents c))))
    (is (eq b (car (object-parents d))))
    (is (eq c (cadr (object-parents d)))))
  (signals object-hierarchy-error
    (with-object-hierarchy (a (b a) (c b) (d a c))
      (declare (ignore d)))))

(def-suite child-caching :in sheeple)
(in-suite child-caching)

(test cache-update-basic
  (with-object-hierarchy (a b (c a))
    (push b (object-parents a))
    (is (equal (list c a b =standard-object= =t=)
               (object-hierarchy-list c)))
    (setf (object-parents c) (list b))
    (is (equal (list c b =standard-object= =t=)
               (object-hierarchy-list c)))
    (push c (object-parents a))
    (is (equal (list a c b =standard-object= =t=)
               (object-hierarchy-list a)))))

(test cache-update-moderate
  (with-object-hierarchy (a (b a) (c a) (d b) (e c) x)
    (push x (object-parents a))
    (is (equal (list a x =standard-object= =t=)
               (object-hierarchy-list a)))
    (is (equal (list b a x =standard-object= =t=)
               (object-hierarchy-list b)))
    (is (equal (list c a x =standard-object= =t=)
               (object-hierarchy-list c)))
    (is (equal (list d b a x =standard-object= =t=)
               (object-hierarchy-list d)))
    (is (equal (list e c a x =standard-object= =t=)
               (object-hierarchy-list e)))))

(test cache-update-extensive
  (with-object-hierarchy (a b c d e f g h)
    (mapcar (lambda (parent object)
              (push parent (object-parents object)))
            (list g f e c d b a c a)
            (list h g h g f e c e d))
    (is (equal (list c a =standard-object= =t=)
               (object-hierarchy-list c)))
    (is (equal (list d a =standard-object= =t=)
               (object-hierarchy-list d)))
    (is (equal (list e c a b =standard-object= =t=)
               (object-hierarchy-list e)))
    (is (equal (list f d a =standard-object= =t=)
               (object-hierarchy-list f)))
    (is (equal (list g c f d a =standard-object= =t=)
               (object-hierarchy-list g)))
    (is (equal (list h e g c f d a b =standard-object= =t=)
               (object-hierarchy-list h)))))

(def-suite inheritance-predicates :in inheritance)
(in-suite inheritance-predicates)

(test parentp
  (let* ((a (object))
         (b (object :parents (list a)))
         (c (object :parents (list b))))
    (is (parentp a b))
    (is (parentp b c))
    (is (not (parentp a c)))
    (is (not (parentp c a)))
    (is (not (parentp b a)))
    (is (not (parentp c b)))))

(test childp
  (let* ((a (object))
         (b (object :parents (list a)))
         (c (object :parents (list b))))
    (is (childp b a))
    (is (childp c b))
    (is (not (childp c a)))
    (is (not (childp a c)))
    (is (not (childp a b)))
    (is (not (childp b c)))))

(test ancestorp
  (let* ((a (object))
         (b (object :parents (list a)))
         (c (object :parents (list b))))
    (is (ancestorp a b))
    (is (ancestorp b c))
    (is (ancestorp a c))
    (is (not (ancestorp c a)))
    (is (not (ancestorp b a)))
    (is (not (ancestorp c b)))))

(test descendantp
  (let* ((a (object))
         (b (object :parents (list a)))
         (c (object :parents (list b))))
    (is (descendantp b a))
    (is (descendantp c b))
    (is (descendantp c a))
    (is (not (descendantp a c)))
    (is (not (descendantp a b)))
    (is (not (descendantp b c)))))

(in-suite creation)
(test object
  ;; basic
  (let ((object (object)))
    (is (objectp object))
    (is (std-object-p object))
    (is (eql =standard-object= (car (object-parents object))))
    (is (eql object (car (object-parents (object :parents (list object))))))
    (is (eql =standard-metaobject= (object-metaobject object))))
  ;; properties arg
  (let ((object (object :properties '((foo bar) (baz quux)))))
    (is (has-direct-property-p object 'foo))
    (is (has-direct-property-p object 'baz))
    (is (eql 'bar (direct-property-value object 'foo)))
    (is (eql 'quux (direct-property-value object 'baz))))
  #+ (or) ;; other metaobject -- Expected failure, left out of v3.0
  (let* ((test-metaobject (object :parents (list =standard-metaobject=) :nickname 'test-metaobject))
         (object (object :metaobject test-metaobject)))
    ;; metaobject tests
    (is (objectp test-metaobject))
    (is (std-object-p test-metaobject))
    (is (eql =standard-metaobject= (object-metaobject test-metaobject)))
    ;; object tests
    (is (objectp object))
    (is (not (std-object-p object)))
    (is (eql test-metaobject (object-metaobject object)))
    (is (eql =standard-object= (car (object-parents object))))))

(test object-nickname
  (let ((object (object)))
    (setf (object-nickname object) 'test)
    (is (eq 'test (object-nickname object)))
    (is (eq 'test (object-nickname (object :parents (list object)))))))

;;;
;;; DEFOBJECT
;;;
(def-suite defobject :in creation)
(in-suite defobject)

;;; macro processing
(test canonize-parents
  (is (equal '(list foo bar baz) (canonize-parents '(foo bar baz))))
  (is (equal '(list) (canonize-parents '())))
  (is (equal '(list foo) (canonize-parents 'foo))))

(test canonize-property
  (is (equal '(list 'VAR "value") (canonize-property '(var "value"))))
  (is (equal '(list 'VAR "value" :accessor 'var)
             (canonize-property '(var "value") t)))
  (is (equal '(list 'VAR "value" :reader nil :accessor 'var)
             (canonize-property '(var "value" :reader nil) t)))
  (is (equal '(list 'VAR "value" :writer nil :accessor 'var)
             (canonize-property '(var "value" :writer nil) t)))
  (is (equal '(list 'VAR "value" :accessor nil)
             (canonize-property '(var "value" :accessor nil) t))))

(test canonize-properties
  (is (equal '(list (list 'VAR "value")) (canonize-properties '((var "value")))))
  (is (equal '(list (list 'VAR "value") (list 'ANOTHER "another-val"))
             (canonize-properties '((var "value") (another "another-val")))))
  (is (equal '(list (list 'VAR "value" :accessor 'var)
               (list 'ANOTHER "another-val" :accessor 'another))
             (canonize-properties '((var "value") (another "another-val")) t))))

(test canonize-options
  (is (equal '(:metaobject foo :other-option 'bar)
             (canonize-options '((:metaobject foo) (:other-option 'bar))))))

(test defobject
  (let* ((parent (object))
         (test-object (defobject (parent) ((var "value")))))
    (is (objectp test-object))
    (is (parentp parent test-object))
    (is (has-direct-property-p test-object 'var))
    ;; TODO - this should also check that reader/writer/accessor combinations are properly added
    ))

;;;
;;; Protos
;;;
(def-suite protos :in creation)
(in-suite protos)

(test defproto
  (let ((test-proto (defproto =test-proto= () ((var "value")))))
    (is (objectp test-proto))
    (is (eql test-proto (symbol-value '=test-proto=)))
    (is (eql =standard-object= (car (object-parents test-proto))))
    (is (objectp (symbol-value '=test-proto=)))
    (is (equal "value" (funcall 'var (symbol-value '=test-proto=))))
    (defproto =test-proto= () ((something-else "another-one")))
    (is (eql test-proto (symbol-value '=test-proto=)))
    (is (eql =standard-object= (car (object-parents test-proto))))
    (signals unbound-property (direct-property-value test-proto 'var))
    (is (equal "another-one" (funcall 'something-else (symbol-value '=test-proto=))))
    (is (equal "another-one" (funcall 'something-else test-proto)))
    ;; TODO - check that options work properly
    (undefreply var (test-proto))
    (undefreply something-else (test-proto))
    (undefine-message 'var)
    (undefine-message 'something-else)
    (makunbound '=test-proto=)
    ))
(test ensure-object)
