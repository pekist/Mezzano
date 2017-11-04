;;;; Copyright (c) 2011-2016 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

(in-package :asdf)

(defsystem "lispos"
  :description "Lisp operating system."
  :version "0"
  :author "Henry Harrington <henry.harrington@gmail.com>"
  :licence "MIT"
  :depends-on (#:nibbles #:cl-ppcre #:iterate
               #:alexandria)
  :serial t
  :components ((:file "compiler/cross")
               (:file "system/data-types")
               (:file "system/parse")
               (:file "system/backquote")
               (:file "compiler/compiler")
               (:file "compiler/environment")
               (:file "compiler/cross-compile")
               (:file "compiler/cross-boot")
               (:file "compiler/lap")
               (:file "compiler/lap-x86")
               (:file "compiler/lap-arm64")
               (:file "compiler/ast")
               (:file "compiler/ast-generator")
               (:file "compiler/keyword-arguments")
               (:file "compiler/simplify-arguments")
               (:file "compiler/pass1")
               (:file "compiler/inline")
               (:file "compiler/lift")
               (:file "compiler/simplify")
               (:file "compiler/constprop")
               (:file "compiler/kill-temps")
               (:file "compiler/value-aware-lowering")
               (:file "compiler/lower-environment")
               (:file "compiler/lower-special-bindings")
               (:file "compiler/simplify-control-flow")
               (:file "compiler/blexit")
               (:file "compiler/transforms")
               (:file "compiler/codegen-x86-64")
               (:file "compiler/branch-tension")
               (:file "compiler/builtins-x86-64/builtins")
               (:file "compiler/builtins-x86-64/array")
               (:file "compiler/builtins-x86-64/character")
               (:file "compiler/builtins-x86-64/cons")
               (:file "compiler/builtins-x86-64/memory")
               (:file "compiler/builtins-x86-64/misc")
               (:file "compiler/builtins-x86-64/numbers")
               (:file "compiler/builtins-x86-64/objects")
               (:file "compiler/builtins-x86-64/unwind")
               (:file "compiler/codegen-arm64")
               (:file "compiler/builtins-arm64/builtins")
               (:file "compiler/builtins-arm64/cons")
               (:file "compiler/builtins-arm64/memory")
               (:file "compiler/builtins-arm64/misc")
               (:file "compiler/builtins-arm64/numbers")
               (:file "compiler/builtins-arm64/objects")
               (:file "compiler/builtins-arm64/unwind")
               (:file "compiler/backend/backend")
               (:file "compiler/backend/cfg")
               (:file "compiler/backend/analysis")
               (:file "compiler/backend/dominance")
               (:file "compiler/backend/convert-ast")
               (:file "compiler/backend/multiple-values")
               (:file "compiler/backend/ssa")
               (:file "compiler/backend/passes")
               (:file "compiler/backend/register-allocation")
               (:file "compiler/backend/x86-64")
               (:file "compiler/backend/x86-64/target")
               (:file "compiler/backend/x86-64/codegen")
               (:file "tools/build-unicode")
               (:file "tools/build-pci-ids")
               (:file "tools/cold-generator")
               (:file "tools/cold-generator-x86-64")
               (:file "tools/cold-generator-arm64")))
