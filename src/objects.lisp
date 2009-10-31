;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; This file is part of Sheeple

;;;; objects.lisp
;;;;
;;;; Object creation, cloning, inspection
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

(defvar *caching-enabled* t)

;; We declare these base vars here so that bootstrapping won't complain.
(define-bound-variables =t= =standard-object= =standard-metaobject=)

;;;
;;; Mold Overview
;;;
;;; Molds act as a sort of "backend class" for objects. A mold is a separate concept from a
;;; metaobject. Their purpose is to offload the stuff that a lot of objects would share into
;;; a single object, and have many similar objects use the data stored in the mold.
;;; Right now, molds are used to keep track of direct properties and store the parents list.
;;; One big win already possible with molds is that they allow us to cache the entire
;;; hierarchy list for an object without having to worry about recalculating it every time
;;; a new object is created.
;;;
;;; In fact, there are two levels of caching going on; molds have their own shared data
;;; storage for 'lineages'. Lineages cache shared parent and hierarchy lists, and are also
;;; cached by objects, so that changes in hierarchy lists get propagated to children.
;;;
;;; A properties-related win is that since we hold information about *which* properties are
;;; available in the mold, our actual object instances can simply carry a lightweight vector
;;; whose slots are indexed into based on information held in the mold. This is identical to
;;; what CLOS implementations often do. Meaning? Direct property access can be as fast as
;;; CLOS' (once similar optimization strategies are implemented).
;;;
;;; There are 4 situations where molds must be handled:
;;; 1. A new object is created: in this case, find or create a new toplevel mold
;;; 2. A property is added: find or create one new transition mold
;;; 3. A property is -removed-: start from top of mold tree, find an acceptable mold
;;; 4. (setf object-parents) is called: begin from the beginning. Object may have properties.
;;;
;;; Every time a mold is switched up, care must be taken that relevant properties are copied
;;; over appropriately, and caches are reset. Additionally, when (setf object-parents) is called,
;;; all sub-molds must be alerted (and they must alert -their- sub-molds), and each sub-mold must
;;; recalculate its hierarchy list.
;;;
;;; One significant problem with the current transition model is that it does not try to reuse
;;; potentially similar transitions. For example, if there are two molds, A and B, an object
;;; that adds property b to mold A will transition to mold AB, whereas adding property a to
;;; mold B will transition to mold BA. Later on, this should (and -will-) be resolved.

;;;
;;; Data definitions
;;;
(deftype property-name ()
  "A valid name for an object's property."
  'symbol)

(deftype transition ()
  "A link to a mold which adds a certain property. Note that transitions
are never dealt with directly -- instead, when a transition's property name
matches a desired property during a search of a mold's transition graph,
the corresponding mold is examined next. Transitions are stored within the
mold-transitions of a `mold'."
  '(cons property-name mold))

(defstruct (mold
             (:predicate moldp)
             (:constructor make-mold (lineage properties)))
  "Also known as 'backend classes', molds are hidden caches which enable
Sheeple to use class-based optimizations yet keep its dynamic power."
  (lineage     nil :read-only t :type lineage) ; A common cache of parent stuff
  (properties  nil :read-only t
               :type (or simple-vector hash-table)) ; Direct properties
  (transitions nil :type (list-of transition))) ; V8-like links to other molds

(define-print-object ((object mold) :identity nil)
  (format t "on ~A" (mold-lineage object)))

(defstruct (lineage
             (:predicate lineagep)
             (:constructor make-lineage
                           (parents &aux (hierarchy (compute-hierarchy parents)))))
  "Information about an object's ancestors and descendants."
  (members (make-weak-hash-table :weakness :key :test 'eq)) ; The lineage's members
  (parents   nil :read-only t) ; A set of objects
  (hierarchy nil)) ; A precedence list of all the lineage's ancestors

(define-print-object ((object lineage) :identity nil)
  (format t "from ~{~{~:[[~A]~;~A~]~}~#[~; and ~:;, ~]~}"
          (mapcar (fun (list (has-direct-property-p _ 'nickname)
                             (object-nickname _)))
                  (lineage-parents object))))

(defun trigger-hierarchy-recalculation (lineage)
  "Updates LINEAGE's hierarchy list, and propagates down the members."
  (with-accessors ((hierarchy lineage-hierarchy)
                   (parents   lineage-parents)
                   (members   lineage-members)) lineage
    (setf hierarchy (compute-hierarchy parents))
    (maphash (lambda (member children)
               (dolist (role (%object-roles member))
                 (clear-dispatch-cache (role-message role)))
               (mapcar 'trigger-hierarchy-recalculation children))
             members)))

(macrolet ((define-mold-reader (name lineage-reader)
             `(defun ,name (mold)
               (,lineage-reader (mold-lineage mold)))))
  (define-mold-reader mold-parents   lineage-parents)
  (define-mold-reader mold-hierarchy lineage-hierarchy))

(defstruct (object (:conc-name %object-) (:predicate objectp)
                   (:constructor std-allocate-object (&optional metaobject))
                   (:print-object print-sheeple-object-wrapper))
  (mold (ensure-mold nil) :type mold)
  (metaobject =standard-metaobject=)
  (property-values nil)
  (roles nil :type list)) ; Roles are used in dispatch -- see reply-foo.lisp

(declaim (inline %object-mold %object-metaobject %object-property-values %object-roles))

(defun %object-children (object)
  (gethash object (lineage-members (mold-lineage (%object-mold object)))))

(defun (setf %object-children) (new-kids object)
  (setf (gethash object (lineage-members (mold-lineage (%object-mold object))))
        new-kids))

;;;
;;; Molds
;;;
(defvar *molds* (make-hash-table :test 'equal)
  "Maps parent lists to their corresponding molds. This is the global entry
point to Sheeple's backend class system.")

(defun find-mold (parents)
  (check-list-type parents object)
  (values (gethash parents *molds*)))

(defun (setf find-mold) (mold parents)
  (check-list-type parents object)
  (check-type mold mold)
  (setf (gethash parents *molds*) mold))

;;;
;;; Transitions
;;;
(defun find-transition (mold property-name)
  "Returns the mold which adds a property named PROPERTY-NAME to MOLD.
If no such mold exists, returns NIL."
  (check-type mold mold)
  (check-type property-name property-name)
  (cdr (assoc property-name (mold-transitions mold) :test 'eq)))

;;;
;;; Mold API -- Retrieval and Automatic Creation of Molds
;;;
(defun ensure-toplevel-mold (parents)
  "Returns the mold for PARENTS, creating and caching a new one if necessary."
  (check-list-type parents object)
  (or (find-mold parents)
      (setf (find-mold parents)
            (make-mold (aprog1 (make-lineage parents)
                         (dolist (parent parents)
                           (push it (%object-children parent))))
                       (vector)))))

(defun ensure-transition (mold property-name)
  "Returns the transition from MOLD indexed by PROPERTY-NAME, creating and
linking a new one if necessary."
  (check-type mold mold)
  (check-type property-name property-name)
  (or (find-transition mold property-name)
      (aconsf (mold-transitions mold) property-name
              (make-mold (mold-lineage mold)
                         (hv-cons property-name (mold-properties mold))))))

(defun ensure-mold (parents &optional (properties #()))
  "Returns the mold with properties PROPERTIES of the mold for PARENTS,
creating and linking a new one if necessary."
  (check-list-type parents object)
  (check-type properties hash-vector)
  (let ((top (ensure-toplevel-mold parents)))
    (do* ((mold top (ensure-transition mold (car props-left)))
          (props-left (hv-elements properties) (cdr props-left)))
         ((null props-left) mold))))

;;;
;;; Objects
;;;
(defun std-object-p (x)
  (when (objectp x)
    (eq (%object-metaobject x) =standard-metaobject=)))

(declaim (inline maybe-std-allocate-object))
(defun maybe-std-allocate-object (metaobject)
  (if (eq =standard-metaobject= metaobject)
      (std-allocate-object metaobject)
      (funcall 'allocate-object metaobject)))

(defun std-print-sheeple-object (object stream)
  (print-unreadable-object (object stream :identity t)
    (format stream "Object ~:[[~S]~;~S~]"
            (ignore-errors (has-direct-property-p object 'nickname))
            (ignore-errors (object-nickname object)))))

(declaim (inline print-sheeple-object-wrapper))
(defun print-sheeple-object-wrapper (object stream)
  (handler-case
      (if (fboundp 'print-sheeple-object)
          (funcall 'print-sheeple-object object stream)
          (std-print-sheeple-object object stream))
    (no-applicable-replies () (std-print-sheeple-object object stream))))

;; The SETF version of this would require that something like CHANGE-METAOBJECT exists.
(defun object-metaobject (object)
  (%object-metaobject object))

(defun object-parents (object)
  (mold-parents (%object-mold object)))

;;; This utility is useful for concisely setting up object hierarchies
(defmacro with-object-hierarchy (object-and-parents &body body)
  "OBJECT-AND-PARENTS is a list, where each element is either a symbol or a list of
the form (OBJECT &REST PARENTS), where OBJECT is a symbol and each of PARENTS is a form
evaluating to produce a object object. Each OBJECT symbol is bound to a object with the
corresponding PARENTS, and the nickname is set to the symbol to facilitate debugging."
  `(let* ,(mapcar (fun (destructuring-bind (object &rest parents) (ensure-list _)
                         `(,object (object :parents ,(when parents ``(,,@parents))
                                           :nickname ',object))))
                  object-and-parents)
     ,@body))

;;;
;;; Inheritance
;;;
(defun validate-parent (parent child)
  (handler-case
      (compute-hierarchy (cons parent (coerce (object-parents child) 'list)))
    (topological-sort-conflict ())))

(defun topological-sort (elements constraints tie-breaker)
  "Sorts ELEMENTS such that they satisfy the CONSTRAINTS, falling back
on the TIE-BREAKER in the case of ambiguous constraints. On the assumption
that they are freshly generated, this implementation is destructive with
regards to the CONSTRAINTS. A future version will undo this change."
  (multiple-value-bind (befores afters) (nunzip-alist constraints)
    (prog (minimal-elements choice result result-tail)
       (declare (list minimal-elements result result-tail))
       top (setf minimal-elements (remove-if (fun (memq _ afters)) elements))
       (when (null minimal-elements) (go end))
       (setf choice (if (null (cdr minimal-elements)) (car minimal-elements)
                        (funcall tie-breaker minimal-elements result))
             elements (delete choice elements :test 'eq)
             (values befores afters) (parallel-delete choice befores afters))
       (unless result (go create-tail))
       (setf (cdr result-tail) (list choice))
       (pop result-tail) (go top) create-tail
       (setf result-tail (list choice) result result-tail) (go top)
       end (if (null elements) (return result)
               (error 'topological-sort-conflict
                      :conflicting-elements elements
                      :sorted-elements result
                      :constraints (mapcar 'cons befores afters))))))

(defun collect-ancestors (object)
  "Collects all of OBJECT's ancestors."
  (do* ((checked nil (cons chosen-object checked))
        (ancestors (copy-list (object-parents object))
                   (dolist (parent (object-parents chosen-object) ancestors)
                     (unless (member parent ancestors)
                       (push parent ancestors))))
        (chosen-object (car ancestors)
                      (dolist (ancestor ancestors)
                        (unless (find ancestor checked :test 'eq)
                          (return ancestor)))))
       ((not chosen-object) ancestors)))

(defun local-precedence-ordering (object)
  "Calculates the local precedence ordering."
  (let ((parents (object-parents object)))
    ;; Since MAPCAR returns once any list is NIL, we only traverse the parent list once.
    (mapcar 'cons (cons object parents) parents)))

(defun std-tie-breaker-rule (minimal-elements chosen-elements)
  ;; Pick the one with a direct leftmost in the hierarchy list computed so far
  (dolist (candidate chosen-elements)
    (awhen (dolist (parent (object-parents candidate))
             (awhen (find parent (the list minimal-elements) :test 'eq) (return it)))
      (return-from std-tie-breaker-rule it))))

(defun compute-hierarchy (parents)
  "Generates an abstract hierarchy out of PARENTS; this would be suitable as
the CDR of the hierarchy-list of a standard object with PARENTS, in order, as
its parents."
  ;; This is VERY far from optimal; however, it's a quick prototype  - Adlai
  (let ((unordered
         (remove-duplicates (append parents (mapcan 'collect-ancestors parents)))))
    (topological-sort
     unordered
     (remove-duplicates (append (mapcar 'cons parents (cdr parents))
                                (mapcan 'local-precedence-ordering unordered)))
     'std-tie-breaker-rule)))

(defun std-compute-object-hierarchy-list (object)
  (cons object (mold-hierarchy (%object-mold object))))

(defun object-hierarchy-list (object)
  "Returns the full hierarchy-list for OBJECT"
  (if (eq =standard-metaobject= (%object-metaobject object))
      (std-compute-object-hierarchy-list object)
      (funcall 'compute-object-hierarchy-list-using-metaobject
               (%object-metaobject object) object)))

;;;
;;; Modifying mold-level stuff
;;;
(defun change-mold (object new-mold)
  "Creates a new property-value vector in OBJECT, according to NEW-MOLD's specification, and
automatically takes care of bringing the correct property-values over into the new vector, in the
right order. Keep in mind that NEW-MOLD might specify some properties in a different order."
  (check-type object object)
  (check-type new-mold mold)
  (let* ((new-properties (mold-properties new-mold))
         (new-values (make-array (hv-length new-properties)))
         (old-values (%object-property-values object)))
    (unless (zerop (length old-values))
      (do-hash-vector (pname position (mold-properties (%object-mold object)))
        (awhen (hv-position pname new-properties)
          (setf (svref new-values it) (svref old-values position)))))
    (unless (eq (mold-lineage new-mold)
                (mold-lineage (%object-mold object)))
      (setf (gethash object (lineage-members (mold-lineage new-mold)))
            (%object-children object))
      (remhash object (lineage-members (mold-lineage (%object-mold object)))))
    (setf (%object-mold object) new-mold
          (%object-property-values object) new-values))
  object)

(defun change-parents (object new-parents)
  "Wraps around `change-mold' to give OBJECT a mold with the requested NEW-PARENTS.
This function has no high-level error checks and SHOULD NOT BE CALLED FROM USER CODE."
  (check-type object object)
  (check-list-type new-parents object)
  (change-mold object (ensure-mold new-parents (mold-properties (%object-mold object))))
  (map 'nil 'trigger-hierarchy-recalculation (%object-children object)))

(defun (setf object-parents) (new-parents object)
  (check-type object object)
  (check-list-type new-parents object)
  (flet ((lose (reason) (error 'object-hierarchy-error :object object :conflict reason)))
    (let ((hierarchy (handler-case (compute-hierarchy new-parents)
                       (topological-sort-conflict (conflict) (lose conflict)))))
      (cond ((null hierarchy) (lose "Hierarchy list is empty"))
            ((find object hierarchy) (lose "Object appears multiple times in hierarchy"))
            (t (change-parents object new-parents)))))
  new-parents)

;;; Inheritance predicates
(defun parentp (maybe-parent child)
  "A parent is a object directly in CHILD's parent list."
  (member maybe-parent (object-parents child)))

(defun ancestorp (maybe-ancestor descendant)
  "A parent is a object somewhere in CHILD's hierarchy list."
  (member maybe-ancestor (cdr (object-hierarchy-list descendant))))

(defun childp (maybe-child parent)
  "A child is a object that has PARENT in its parent list."
  (parentp parent maybe-child))

(defun descendantp (maybe-descendant ancestor)
  "A descendant is a object that has ANCESTOR in its hierarchy-list."
  (ancestorp ancestor maybe-descendant))

;;;
;;; Spawning
;;;
(defun object (&rest all-keys
               &key (parents (list =standard-object=))
               (metaobject =standard-metaobject=) &allow-other-keys
               &aux (object (maybe-std-allocate-object metaobject))
                    (parents (or (ensure-list parents) (list =standard-object=))))
  "Returns a new object with PARENTS as its parents. METAOBJECT is used as the metaobject when
allocating the new object object. ALL-KEYS is passed on to INIT-OBJECT."
  (declare (dynamic-extent all-keys))
  (handler-case
      (setf (%object-mold object) (ensure-mold parents))
    (topological-sort-conflict (conflict)
      (error 'object-hierarchy-error :object object :conflict conflict)))
  (setf (%object-children object) nil)
  (let ((*caching-enabled* nil))
    (apply 'init-object object all-keys)))

(defun clone (object &optional (metaobject (%object-metaobject object)))
  "Creates a object with the same parents and metaobject as OBJECT. If supplied, METAOBJECT
will be used instead of OBJECT's metaobject, but OBJECT itself remains unchanged."
  (when (eq =t= object)
    (error 'fuck-off :format-control "You ain't allowed to clone =T=. Shoo."))
  (aprog1 (maybe-std-allocate-object metaobject)
    (change-mold it (%object-mold object))
    (with-accessors ((roles %object-roles)
                     (props %object-property-values)) object
      (setf (%object-roles it)           (copy-list          roles)
            (%object-property-values it) (when props (copy-simple-vector props))))))

;;;
;;; Fancy Macros
;;;
(defun canonize-parents (parents)
  `(list ,@(ensure-list parents)))

(defun canonize-properties (properties &optional (accessors-by-default nil))
  `(list ,@(mapcar (rcurry 'canonize-property accessors-by-default) properties)))

(defun canonize-property (property &optional (accessors-by-default nil))
  (let* ((property-name (if (consp property) (car property) property))
         (property-value (when (consp property) (cadr property)))
         (rest-of-property (when (consp property) (cddr property)))
         (add-accessor-p (and (if (consp property) (not (find :accessor (cddr property))) t)
                              accessors-by-default)))
    `(list ',property-name ,property-value ,@rest-of-property
           ,@(when add-accessor-p `(:accessor ',property-name)))))

(defun canonize-options (options)
  (mapcan 'canonize-option options))

(defun canonize-option (option)
  (list (car option) (cadr option)))

(defmacro defobject (objects properties &rest options)
  "Standard object-generation macro."
  `(object :parents ,(canonize-parents objects)
           :properties ,(canonize-properties properties)
           ,@(canonize-options options)))

(defmacro defproto (name objects properties &rest options)
  "Words cannot express how useful this is."
  (let (messages)
    (dolist (property-spec (mapcar 'cdr (cdr (canonize-properties properties t))))
      (loop with type and name do
           (setf (values type name property-spec)
                 (get-properties property-spec '(:accessor :reader :writer)))
           (setf property-spec (cddr property-spec))
         while type when name do
           (flet ((add-reader (name)
                    (push `(ensure-message ,name :lambda-list '(object)) messages))
                  (add-writer (name)
                    (push `(ensure-message ,name :lambda-list '(new-value object)) messages)))
             (case type
               (:accessor (add-reader name)
                          (add-writer ``(setf ,,name)))
               (:reader (add-reader name))
               (:writer (add-writer name))))))
    `(progn
       (declaim (special ,name))
       ,@ (when messages ; Space necessary for indentation... :(
            `((eval-when (:compile-toplevel) ,@messages)))
       (setf (symbol-value ',name)
             (ensure-object (when (boundp ',name)
                              (symbol-value ',name))
                            ,(canonize-parents objects)
                            :properties ,(canonize-properties properties t)
                            ,@(canonize-options options)
                            :nickname ',name)))))

(defun ensure-object (maybe-object parents &rest options)
  (if maybe-object
      (apply 'reinit-object maybe-object :parents parents options)
      (apply 'object :parents parents options)))
