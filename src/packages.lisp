;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10; indent-tabs-mode: nil -*-

(defpackage #:%sheeple-garbage
  (:use :cl)
  (:shadow :make-hash-table)
  (:export #:gc #:weak-pointer
           #:make-weak-pointer
           #:weak-pointer-value
           #:weak-pointer-p
           #:maybe-make-weak-pointer
           #:maybe-weak-pointer-value
           #:make-weak-hash-table
           #:hash-table-weakness
           #:finalize
           #:cancel-finalization))

(defpackage #:sheeple
  (:use :cl :%sheeple-garbage)
  (:export

   ;; Objects
   #:object #:defobject #:defproto #:objectp #:object-parents #:ancestorp #:parentp
   #:descendantp #:childp #:init-object #:shared-init #:reinit-object #:print-sheeple-object
   #:object-nickname #:object-hierarchy-list

   ;; Property access
   #:add-property #:property-value #:direct-property-value #:available-properties
   #:remove-property #:remove-all-direct-properties #:property-owner #:has-property-p
   #:has-direct-property-p #:with-properties #:object-direct-properties

   ;; Messages
   #:defmessage #:defreply #:available-replies #:undefmessage #:undefreply #:participantp
   #:call-next-reply #:next-reply-p

   ;; Protos
   #:=standard-object= #:=t= #:=null= #:=symbol= #:=complex= #:=integer= #:=float= #:=cons=
   #:=character= #:=hash-table= #:=package= #:=pathname= #:=readtable= #:=stream= #:=number=
   #:=string= #:=bit-vector= #:=vector= #:=array= #:=function= #:=boxed-object=

   ;; built-ins
   #:box-type-of #:find-boxed-object #:objectify

   ;; Conditions
   #:sheeple-error #:sheeple-warning #:topological-sort-conflict #:object-hierarchy-error
   #:object-property-error #:unbound-property #:unbound-direct-property
   #:clobbering-function-definition #:sheeple-message-error #:insufficient-message-args
   #:no-such-message #:message-lambda-list-error #:sheeple-reply-error #:reply-argument-conflict
   #:automatic-message-creation #:reply-lambda-list-conflict #:no-applicable-replies
   #:no-primary-replies #:specialized-lambda-list-error
   ))

(defpackage #:sheeple-user
  (:use :cl :sheeple))
