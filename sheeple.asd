(asdf:defsystem sheeple
  :version "0.1"
  :description "Cheeky prototypes for Common Lisp"
  :author "Kat Marchan <zkat at sykosomatic-dot-org>"
  :licence "MIT"
  :depends-on (:closer-mop)
  :serial t
  :components 
  ((:module src
	    :serial t
	    :components
	    ((:file "trivial-garbage")
	     (:file "packages")
	     (:file "conditions")
	     (:file "utils")
	     (:file "properties")
	     (:file "sheeple")
	     (:file "clone")
	     (:file "wolves")
	     (:file "parse-lambda-list")
	     (:file "buzzwords")
	     (:file "message-generation")
	     (:file "message-dispatch")
	     (:file "bootstrap")
	     (:file "post-boot")
	     (:file "glue")))))



