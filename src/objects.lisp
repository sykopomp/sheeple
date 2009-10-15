;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

;;;; This file is part of Sheeple

;;;; objects.lisp
;;;;
;;;; Object creation, cloning, inspection
;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package :sheeple)

;; We declare these base vars here so that bootstrapping won't complain.
(define-bound-variables =t= =standard-object= =standard-metaobject=)

(defvar *bootstrappedp* nil)

;;;
;;; Molds
;;;
;;; - Molds act as a sort of "backend class" for objects. A mold is a separate concept from a
;;;   metaobject. Their purpose is to offload the stuff that a lot of objects would share into
;;;   a single object, and have many similar objects use the data stored in the mold.
;;;   Right now, molds are used to keep track of direct properties and store the parents list.
;;;   One big win already possible with molds is that they allow us to cache the entire
;;;   hierarchy list for an object without having to worry about recalculating it every time
;;;   a new object is created.
;;;
;;;   A properties-related win is that since we hold information about *which* properties are
;;;   available in the mold, our actual object instances can simply carry a lightweight vector
;;;   whose slots are indexed into based on information held in the mold. This is identical to
;;;   what CLOS implementations often do. Meaning? Direct property access can be as fast as
;;;   CLOS' (once similar optimization strategies are implemented).
;;;
;;;   There are 4 situations where molds must be handled:
;;;   1. A new object is created: in this case, find or create a new toplevel mold
;;;   2. A property is added: find or create one new transition mold
;;;   3. A property is -removed-: start from top of mold tree, find an acceptable mold
;;;   4. (setf object-parents) is called: begin from the beginning. Object may have properties.
;;;
;;;   Every time a mold is switched up, care must be taken that relevant properties are copied
;;;   over appropriately, and caches are reset. Additionally, when (setf object-parents) is called,
;;;   all sub-molds must be alerted (and they must alert -their- sub-molds), and each sub-mold must
;;;   recalculate its hierarchy list.

(defstruct (mold-top (:predicate moldp)
                     (:constructor
                      %make-mold (parents &aux (hierarchy (compute-hierarchy parents)))))
  "Also known as 'backend classes', molds are hidden caches which enable
Sheeple to use class-based optimizations yet keep its dynamic power."
  (parents   nil :read-only t)
  (hierarchy nil)
  (sub-molds nil)
  initial-node)

(defstruct (node (:predicate nodep))
  "Transitions are auxiliary data structures for molds, storing information
about an object's direct properties. Objects keep a reference to their
current transition as an entry point to the mold datastructure."
  (mold        nil :read-only t :type mold)
  (properties  nil :read-only t)
  (transitions nil))

(deftype property-name ()
  "A valid name for an object's property."
  'symbol)

(deftype transition ()
  "A link to a node which adds a certain property. Note that transitions
are never dealt with directly -- instead, when a transition's property name
matches a desired property during a search of a mold's transition graph,
the corresponding node is examined next. Transitions are stored within the
node-transitions of a `node'."
  '(cons property-name node))

(deftype mold ()
  "A union of NODE and MOLT-TOP, mainly here for convenience:
  (typep (ensure-mold <parents> <properties>) 'mold) => T"
  '(or node mold-top))

(defun make-mold (parents)
  (aprog1 (%make-mold parents)
    (setf (mold-top-initial-node it)
          (make-node :mold it))))

(macrolet ((define-node-mold-function (name inner docstring)
             `(defun ,name (mold) ,docstring
                (etypecase mold
                  (mold-top (,inner mold))
                  (node (,name (node-mold mold)))))))
  (define-node-mold-function mold-parents mold-top-parents
    "Returns the parents of MOLD, which can be either a `mold' or a `node'.")
  (define-node-mold-function mold-hierarchy mold-top-hierarchy
    "Returns the hierarchy list of MOLD, which can be either a `mold' or a `node'.")
  (define-node-mold-function mold-sub-molds mold-top-sub-molds
    "Returns the cached child molds of MOLD, which can be either a `mold' or a `node'."))

(defun mold-properties (mold)
  "Returns the properties of MOLD, which should be a `node'."
  (if (typep mold 'node)
      (node-properties mold)
      (error 'type-error :datum mold :expected-type 'node)))

(defvar *molds* (make-hash-table :test 'equal)
  "Maps parent lists to their corresponding molds. This is the global entry
point to Sheeple's backend class system.")

(defun find-mold (parents)
  (check-list-type parents object)
  (values (gethash parents *molds*)))

(defun (setf find-mold) (mold parents)
  (check-list-type parents object)
  (check-type mold mold-top)
  (setf (gethash parents *molds*) mold))

;;;
;;; Transitions
;;;
(defun find-transition (node property-name)
  "Returns the node which adds a property named PROPERTY-NAME to NODE.
If no such node exists, returns NIL."
  (check-type node node)
  (check-type property-name property-name)
  (cdr (assoc property-name (node-transitions node) :test 'eq)))

(defun find-node-by-transitions (start-node goal-properties)
  "Searches the transition tree from START-NODE to find the node containing
GOAL-PROPERTIES, returning that node if found, or NIL on failure."
  (check-type start-node node)
  (check-list-type goal-properties property-name)
  ;; This algorithm is very concise, but it's not optimal AND it's unclear.
  ;; Probably the first target for cleaning up. - Adlai
  (let ((path (set-difference goal-properties (node-properties start-node))))
    (if (null path) start-node
        (awhen (some (fun (find-transition start-node _)) path)
          (find-node-by-transitions it path)))))

;;;
;;; Mold API -- Retrieval and Automatic Creation of Molds and Nodes
;;;
(defun ensure-toplevel-mold (parents)
  "Returns the mold for PARENTS, creating and caching a new one if necessary."
  (check-list-type parents object)
  (or (find-mold parents)
      (setf (find-mold parents)
            (make-mold parents))))

(defun ensure-transition (node property-name)
  "Returns the transition from NODE indexed by PROPERTY-NAME, creating and
linking a new one if necessary."
  (check-type node node)
  (check-type property-name property-name)
  (or (find-transition node property-name)
      (aconsf (node-transitions node) property-name
              (make-node :mold (node-mold node)
                         :properties (cons property-name
                                           (node-properties node))))))

(defun ensure-mold (parents properties)
  "Returns the node with properties PROPERTIES of the mold for PARENTS,
creating and linking a new one if necessary."
  (check-list-type parents object)
  (check-list-type properties property-name)
  (let ((mold (ensure-toplevel-mold parents)))
    (do* ((node (mold-top-initial-node mold)
                (ensure-transition node (car props-left)))
          (props-left properties (cdr props-left)))
        ((null props-left) node))))

;;;
;;; Switching molds
;;;
(defun change-node (object new-node)
  "Creates a new property-value vector in OBJECT, according to NEW-NODE's specification, and
automatically takes care of bringing the correct property-values over into the new vector, in the
right order. Keep in mind that NEW-NODE might specify some properties in a different order."
  ;; TODO
  (let* ((old-node (%object-mold object))
         (old-properties (mold-properties old-node))
         (old-values (%object-property-values object)))
    (if old-values
        :move-values-over
        (setf (%object-property-values object)
              (make-array (length (mold-properties new-node)))
              (%object-mold object) new-node))))

;;;
;;; Objects
;;;
(defstruct (object (:conc-name %object-) (:predicate objectp)
                   (:constructor std-allocate-object (metaobject))
                   (:print-object print-sheeple-object-wrapper))
  mold ; mold this object currently refers to
  metaobject ; metaobject used by the MOP for doing various fancy things
  (property-values nil) ; either NIL, or a vector holding direct property values
  (roles nil)) ; a list of role objects belonging to this object.

(declaim (inline %object-mold %object-metaobject %object-property-values %object-roles))

(defun std-object-p (x)
  (ignore-errors (eq (%object-metaobject x) =standard-metaobject=)))

(defun maybe-std-allocate-object (metaobject)
  (if (eq =standard-metaobject= metaobject)
      (std-allocate-object metaobject)
      (allocate-object metaobject)))

(defun std-print-sheeple-object (object stream)
  (print-unreadable-object (object stream :identity t)
    (format stream "Object ~:[[~S]~;~S~]"
            (ignore-errors (has-direct-property-p object 'nickname))
            (ignore-errors (object-nickname object)))))

(declaim (inline print-sheeple-object-wrapper))
(defun print-sheeple-object-wrapper (object stream)
  (handler-case
      (if (fboundp 'print-sheeple-object)
          (print-sheeple-object object stream)
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
                         `(,object (make-object ,(when parents ``(,,@parents))
                                              :nickname ',object))))
                  object-and-parents)
     ,@body))

;;;
;;; Inheritance
;;;
(defun validate-parent (parent child)
  ;; TODO
  t)

(defun topological-sort (elements constraints tie-breaker)
  "Sorts ELEMENTS such that they satisfy the CONSTRAINTS, falling back
on the TIE-BREAKER in the case of ambiguous constraints. On the assumption
that they are freshly generated, this implementation is destructive with
regards to the CONSTRAINTS. A future version will undo this change."
  (multiple-value-bind (befores afters) (nunzip-alist constraints)
    (loop for minimal-elements = (remove-if (fun (memq _ afters)) elements)
       while minimal-elements
       for choice = (if (null (cdr minimal-elements))
                        (car minimal-elements)
                        (funcall tie-breaker minimal-elements result))
       with result do (push choice result)
         (setf elements (delete choice elements :test 'eq)
               (values befores afters) (parallel-delete choice befores afters))
       finally (if (null elements)
                   (return-from topological-sort (nreverse result))
                   (error "Inconsistent precedence graph.")))))

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
  (dolist (candidate chosen-elements)
    (awhen (dolist (parent (object-parents candidate))
             (awhen (find parent (the list minimal-elements) :test 'eq) (return it)))
      (return-from std-tie-breaker-rule it))))

(defun compute-hierarchy (parents)
  "Generates an abstract hierarchy out of PARENTS; this would be suitable as
the CDR of the hierarchy-list of a standard object with PARENTS, in order, as
its parents."
  ;; This is VERY far from optimal; however, it's a quick prototype  - Adlai
  (handler-case
      (let ((unordered
             (remove-duplicates (append parents (mapcan 'collect-ancestors parents)))))
        (topological-sort
         unordered
         (remove-duplicates (append (mapcar 'cons parents (cdr parents))
                                    (mapcan 'local-precedence-ordering unordered)))
         'std-tie-breaker-rule))
    (simple-error ()
      (error "Bad juju in experimental code. This is a bug in Sheeple."))))

(defun object-hierarchy-list (object)
  "Returns the full hierarchy-list for OBJECT"
  (cons object (mold-hierarchy (%object-mold object))))

(defun (setf object-parents) (new-parent-list object)
  ;; TODO - this needs some careful writing, validation of the hierarchy-list, new mold, etc.
  (change-node object (ensure-mold new-parent-list (mold-properties (%object-mold object))))
  new-parent-list)

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
(defun make-object (parent* &rest all-keys
                    &key (metaobject =standard-metaobject=) &allow-other-keys)
  "Creates a new object with OBJECTS as its parents. METAOBJECT is used as the metaobject when
allocating the new object object. ALL-KEYS is passed on to INIT-OBJECT."
  (declare (dynamic-extent all-keys))
  (let ((mold (ensure-mold (ensure-list (or parent* =standard-object=)) nil))
        (obj (maybe-std-allocate-object metaobject)))
    (setf (%object-mold obj) mold)
    (apply 'init-object obj all-keys)
    obj))

(defun spawn (&rest objects)
  "Creates a new standard-object object with OBJECTS as its parents."
  (declare (dynamic-extent objects))
  (make-object objects))

;; Feel free to change the exact interface if you don't like it. -- Adlai
(defun clone (object &optional (metaobject (object-metaobject object)))
  "Creates a object with the same parents and metaobject as OBJECT. If supplied, METAOBJECT
will be used instead of OBJECT's metaobject, but OBJECT itself remains unchanged."
  ;; TODO!!! - is this good enough? - syko
  (let ((new-obj (allocate-object metaobject)))
    (setf (%object-mold new-obj)
          (%object-mold object)
          (%object-property-values new-obj)
          (make-array (length (%object-property-values object))
                      :initial-contents (%object-property-values object))
          (%object-roles new-obj)
          (copy-list (%object-roles object))) ;this won't break anything, right? - syko
    new-obj))

;;;
;;; fancy macros
;;;
(defun canonize-objects (objects)
  `(list ,@objects))

(defun canonize-properties (properties &optional (accessors-by-default nil))
  `(list ,@(mapcar (rcurry 'canonize-property accessors-by-default) properties)))

(defun canonize-property (property &optional (accessors-by-default nil))
  `(list ',(car property) ,@(cdr property)
         ,@(when (and (not (find :accessor (cddr property)))
                      accessors-by-default)
                 `(:accessor ',(car property)))))

(defun canonize-options (options)
  (mapcan 'canonize-option options))

(defun canonize-option (option)
  (list (car option) (cadr option)))

(defmacro defobject (objects properties &rest options)
  "Standard object-generation macro. This variant auto-generates accessors."
  `(make-object
    ,(canonize-objects objects)
    :properties ,(canonize-properties properties)
    ,@(canonize-options options)))

(defmacro defproto (name objects properties &rest options)
  "Words cannot express how useful this is."
  `(progn
     (declaim (special ,name))
     (let ((object (ensure-object
                   (when (boundp ',name) (symbol-value ',name))
                   ,(canonize-objects objects)
                   :properties ,(canonize-properties properties t)
                   ,@(canonize-options options))))
       (unless (or (not *bootstrappedp*) (has-direct-property-p object 'nickname))
         (setf (object-nickname object) ',name))
       (setf (symbol-value ',name) object))))

(defun ensure-object (maybe-object parents &rest options)
  (if maybe-object
      (apply 'reinit-object maybe-object :parents parents options)
      (apply 'make-object parents options)))
