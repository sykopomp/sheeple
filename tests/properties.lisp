;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;;
;;;; This file is part of Sheeple.

;;;; tests/properties.lisp
;;;;
;;;; Unit tests for src/properties.lisp
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

;;;
;;; Properties
;;;
(def-suite properties :in sheeple)

(def-suite internals :in properties)
(in-suite internals)

(postboot-test %add-property-cons
  (let ((sheep (spawn))
        (property
         #+sheeple3.1 (spawn =standard-property=)
         #-sheeple3.1 'test))
    (is (null (%sheep-direct-properties sheep)))
    (is (eq sheep (%add-property-cons sheep property nil)))
    (signals error (%add-property-cons sheep property nil))
    (is (not (null (%sheep-direct-properties sheep))))
    (is (vectorp (%sheep-direct-properties sheep)))
    (is (find property (%sheep-direct-properties sheep)
              :key #+sheeple3.1(fun (property-name (car _)))
              #-sheeple3.1 'car))))

(postboot-test %get-property-cons
  (let* ((sheep (spawn))
         (property
          #+sheeple3.1 (defsheep (=standard-property=) ((property-name 'test)))
          #-sheeple3.1 'test)
         (other-property
          #+sheeple3.1 (defsheep (=standard-property=) ((property-name 'other-prop)))
          #-sheeple3.1 'other-prop))
    (is (null (%get-property-cons sheep property)))
    (%add-property-cons sheep property 'value)
    (is (consp (%get-property-cons sheep property))))
    (is (null (%get-property-cons sheep other-property)))
    (is (eq property (car (%get-property-cons sheep property))))
    (is (eq 'value (cdr (%get-property-cons sheep property)))))

(postboot-test %remove-property-cons
  (let* ((sheep (spawn))
         (property
          #+sheeple3.1 (defsheep (=standard-property=) ((property-name 'test)))
          #-sheeple3.1 'test))
    (%add-property-cons sheep property 'value)
    (is (eq sheep (%remove-property-cons sheep 'test)))
    (is (null (%get-property-cons sheep 'tests)))))

(postboot-test %direct-property-value
  (let* ((sheep (spawn))
         (property
          #+sheeple3.1 (defsheep (=standard-property=) ((property-name 'test)))
          #-sheeple3.1 'test))
    (%add-property-cons sheep property 'value)
    (is (eq 'value (%direct-property-value sheep 'test)))))

#+sheeple3.1
(postboot-test %direct-property-metaobject
  (let* ((sheep (spawn))
         (property
          #+sheeple3.1 (defsheep (=standard-property=) ((property-name 'test)))
          #-sheeple3.1 'test))
    (%add-property-cons sheep property 'value)
    (is (eq 'new-value (setf (%direct-property-value sheep 'test) 'new-value)))
    (is (eq 'new-value (%direct-property-value sheep 'test)))))

(def-suite existential :in properties)
(in-suite existential)

(postboot-test has-direct-property-p
  (let* ((sheep (spawn))
         (property
          #+sheeple3.1 (defsheep (=standard-property=) ((property-name 'test)))
          #-sheeple3.1 'test))
    (%add-property-cons sheep property 'value)
    (is (has-direct-property-p sheep 'test))
    (is (not (has-direct-property-p sheep 'something-else))))
  (let* ((a (spawn))
         (b (spawn a)))
    (add-property a 'test 'value)
    (is (has-direct-property-p a 'test))
    (is (not (has-direct-property-p b 'test)))))

(postboot-test has-property-p
  (let* ((a (spawn))
         (b (spawn a)))
    (add-property a 'test 'value)
    (is (has-direct-property-p a 'test))
    (is (not (has-direct-property-p a 'something-else)))
    (is (not (has-direct-property-p b 'test)))
    (is (not (has-direct-property-p b 'something-else)))))

(postboot-test add-property
  (let ((sheep (spawn)))
    (is (eq sheep (add-property sheep 'test 'value)))
    (is (has-direct-property-p sheep 'test))
    (is (eq 'value (%direct-property-value sheep 'test)))
    (signals error (add-property sheep "foo" "uh oh"))
    (is (not (has-direct-property-p sheep "foo")))
    ;; todo - check that the restart works properly.
    ))

(postboot-test remove-property
  (let ((sheep (spawn)))
    (signals error (remove-property sheep 'something))
    (add-property sheep 'test 'value)
    (is (eq sheep (remove-property sheep 'test)))
    (is (not (has-direct-property-p sheep 'test)))
    (signals error (remove-property sheep 'test))))

(postboot-test remove-all-direct-properties
  (let ((sheep (spawn)))
    (add-property sheep 'test1 'value)
    (add-property sheep 'test2 'value)
    (add-property sheep 'test3 'value)
    (is (eq sheep (remove-all-direct-properties sheep)))
    (is (not (or (has-direct-property-p sheep 'test1)
                 (has-direct-property-p sheep 'test2)
                 (has-direct-property-p sheep 'test3))))))

(def-suite values :in properties)
(in-suite values)

(postboot-test direct-property-value
  (let* ((a (spawn))
         (b (spawn a)))
    (add-property a 'test 'value)
    (is (eq 'value (direct-property-value a 'test)))
    (signals unbound-property (direct-property-value a 'something-else))
    (signals unbound-property (direct-property-value b 'test))))

(postboot-test property-value
  (let* ((a (spawn))
         (b (spawn a))
         (c (spawn)))
    (add-property a 'test 'value)
    (is (eq 'value (property-value a 'test)))
    (is (eq 'value (property-value b 'test)))
    (signals unbound-property (property-value a 'something-else))
    (signals unbound-property (property-value c 'test))))

(postboot-test property-value-with-hierarchy-list
  (let* ((a (spawn))
         (b (spawn a))
         (c (spawn)))
    (add-property a 'test 'value)
    (is (eq 'value (property-value-with-hierarchy-list a 'test)))
    (is (eq 'value (property-value-with-hierarchy-list b 'test)))
    (signals unbound-property (property-value-with-hierarchy-list a 'something-else))
    (signals unbound-property (property-value-with-hierarchy-list c 'test))))

(postboot-test setf-property-value
  (let* ((a (spawn))
         (b (spawn a)))
    (signals unbound-property (setf (property-value a 'test) 'new-val))
    (add-property a 'test 'value)
    (is (eq 'new-value (setf (property-value a 'test) 'new-value)))
    (is (eq 'new-value (direct-property-value a 'test)))
    (is (eq 'new-value (property-value b 'test)))
    (is (eq 'foo (setf (property-value b 'test) 'foo)))
    (is (eq 'foo (property-value b 'test)))
    (is (eq 'new-value (property-value a 'test)))))

(def-suite reflection :in properties)
(in-suite reflection)

(postboot-test property-owner
  (let* ((parent (defsheep () ((var "value"))))
         (child (defsheep (parent) ((child-var "child-value")))))
    (is (eq parent (property-owner parent 'var)))
    (is (eq parent (property-owner child 'var)))
    (is (eq child (property-owner child 'child-var)))
    (is (null (property-owner parent 'some-other-property nil)))
    (signals unbound-property (property-owner parent 'some-other-property))
    (signals unbound-property (property-owner parent 'some-other-property t))))

#+sheeple3.1
(postboot-test property-metaobject-p
  (is (property-metaobject-p (spawn =standard-property=)))
  (is (not (property-metaobject-p (spawn)))))

#+sheeple3.1
(postboot-test direct-property-metaobject
  (let ((sheep (defsheep () ((var 'value)))))
    (is (property-metaobject-p (direct-property-metaobject sheep 'var)))
    (signals unbound-property (direct-property-metaobject sheep 'durr))
    (is (null (direct-property-metaobject sheep 'durr nil)))
    (signals unbound-property (direct-property-metaobject sheep 'durr t))))

(postboot-test sheep-direct-properties
  (let ((sheep (defsheep () ((var1 'val) (var2 'val) (var3 'val)))))
    (is (= 3 (length (sheep-direct-properties sheep))))
    (is (every #+sheeple3.1 #'property-metaobject-p
               #-sheeple3.1 #'symbolp
               (sheep-direct-properties sheep)))))

(postboot-test available-properties
  (let* ((a (defsheep () ((var1 'val))))
         (b (defsheep (a) ((var2 'val))))
         (c (defsheep (b) ((var3 'val)))))
    (is (= 3 (length (available-properties sheep))))
    (is (every #+sheeple3.1 #'property-metaobject-p
               #-sheeple3.1 #'symbolp (available-properties sheep)))))

;; ugh. I don't want to write tests for these.
(postboot-test property-summary)
(postboot-test direct-property-summary)
