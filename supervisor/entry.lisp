(in-package :mezzanine.supervisor)

;;; FIXME: Should not be here.
;;; >>>>>>

(defun sys.int::current-thread ()
  (current-thread))

(defun integerp (object)
  (sys.int::fixnump object))

(defun sys.int::%coerce-to-callable (object)
  (etypecase object
    (function object)
    (symbol
     (sys.int::%array-like-ref-t
      (sys.int::%array-like-ref-t object sys.c::+symbol-function+)
      sys.int::+fref-function+))))

;; Hardcoded string accessor, the support stuff for arrays doesn't function at this point.
(defun char (string index)
  (assert (sys.int::character-array-p string) (string))
  (let ((data (sys.int::%array-like-ref-t string 0)))
    (assert (and (<= 0 index)
                 (< index (sys.int::%object-header-data data)))
            (string index))
    (code-char
     (case (sys.int::%object-tag data)
       (#.sys.int::+object-tag-array-unsigned-byte-8+
        (sys.int::%array-like-ref-unsigned-byte-8 data index))
       (#.sys.int::+object-tag-array-unsigned-byte-16+
        (sys.int::%array-like-ref-unsigned-byte-16 data index))
       (#.sys.int::+object-tag-array-unsigned-byte-32+
        (sys.int::%array-like-ref-unsigned-byte-32 data index))
       (t 0)))))

(defun length (sequence)
  (if (sys.int::character-array-p sequence)
      (sys.int::%array-like-ref-t sequence 3)
      nil))

(defun code-char (code)
  (sys.int::%%assemble-value (ash code 4) sys.int::+tag-character+))

(defun char-code (character)
  (logand (ash (sys.int::lisp-object-address character) -4) #x1FFFFF))

(declaim (special sys.int::*newspace* sys.int::*newspace-offset*))

(defvar *allocator-lock*)

(defvar *2g-allocation-bump*)
(defvar *allocation-bump*)

(defvar sys.int::*boot-area-base*)
(defvar sys.int::*boot-area-bump*)

;; TODO?
(defmacro with-gc-deferred (&body body)
  `(progn
     ,@body))

(defun %allocate-object (tag data size area)
  (assert (eql area :wired))
  (let ((words (1+ size)))
    (when (oddp words)
      (incf words))
    (assert (<= (+ sys.int::*boot-area-bump* (* words 8)) #x200000))
    (with-symbol-spinlock (*allocator-lock*)
      (let ((addr (+ sys.int::*boot-area-base* sys.int::*boot-area-bump*)))
        (incf sys.int::*boot-area-bump* (* words 8))
        ;; Write array header.
        (setf (sys.int::memref-unsigned-byte-64 addr 0)
              (logior (ash tag sys.int::+array-type-shift+)
                      (ash data sys.int::+array-length-shift+)))
        (sys.int::%%assemble-value addr sys.int::+tag-object+)))))

(defun sys.int::make-simple-vector (size &optional area)
  (%allocate-object sys.int::+object-tag-array-t+ size size area))

(defun sys.int::%make-struct (size &optional area)
  (%allocate-object sys.int::+object-tag-structure-object+ size size area))

(defun sys.int::cons-in-area (car cdr &optional area)
  (assert (eql area :wired))
  (assert (<= (+ sys.int::*boot-area-bump* (* 4 8)) #x200000))
  (with-symbol-spinlock (*allocator-lock*)
    (let ((addr (+ sys.int::*boot-area-base* sys.int::*boot-area-bump*)))
      (incf sys.int::*boot-area-bump* (* 4 8))
      ;; Set header.
      (setf (sys.int::memref-t addr 0) (ash sys.int::+object-tag-cons+ sys.int::+array-type-shift+))
      ;; Set car/cdr.
      (setf (sys.int::memref-t addr 2) car
            (sys.int::memref-t addr 3) cdr)
      (sys.int::%%assemble-value (+ addr 16) sys.int::+tag-cons+))))

(defun stack-base (stack)
  (car stack))

(defun stack-size (stack)
  (cdr stack))

(defun %allocate-stack (size)
  ;; 2M align stacks.
  (incf size #x1FFFFF)
  (setf size (logand size (lognot #x1FFFFF)))
  (let* ((addr (with-symbol-spinlock (*allocator-lock*)
                 (prog1 sys.int::*allocation-bump*
                   (incf sys.int::*allocation-bump* (+ size #x200000)))))
         (extent (make-store-extent :store-base nil
                                    :virtual-base addr
                                    :size size
                                    :wired-p nil
                                    :type :stack
                                    :zero-fill t)))
    (setf *extent-table* (sys.int::cons-in-area extent *extent-table* :wired))
    (sys.int::cons-in-area addr size :wired)))

;; TODO.
(defun sleep (seconds)
  nil)

(sys.int::define-lap-function sys.int::%%coerce-fixnum-to-float ()
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:sar64 :rax #.sys.int::+n-fixnum-bits+)
  (sys.lap-x86:cvtsi2ss64 :xmm0 :rax)
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.sys.int::+tag-single-float+))
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(sys.int::define-lap-function sys.int::%%float-+ ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Add.
  (sys.lap-x86:addss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.sys.int::+tag-single-float+))
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(sys.int::define-lap-function sys.int::%%float-- ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Add.
  (sys.lap-x86:subss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.sys.int::+tag-single-float+))
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(sys.int::define-lap-function sys.int::%%float-< ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Compare.
  (sys.lap-x86:ucomiss :xmm0 :xmm1)
  (sys.lap-x86:mov64 :r8 nil)
  (sys.lap-x86:mov64 :r9 t)
  (sys.lap-x86:cmov64b :r8 :r9)
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(defun sys.int::generic-+ (x y)
  (cond ((or (floatp x)
             (floatp y))
         (when (sys.int::fixnump x)
           (setf x (sys.int::%%coerce-fixnum-to-float x)))
         (when (sys.int::fixnump y)
           (setf y (sys.int::%%coerce-fixnum-to-float y)))
         (sys.int::%%float-+ x y))
        (t (error "Unsupported argument combination."))))

(defun sys.int::generic-- (x y)
  (cond ((or (floatp x)
             (floatp y))
         (when (sys.int::fixnump x)
           (setf x (sys.int::%%coerce-fixnum-to-float x)))
         (when (sys.int::fixnump y)
           (setf y (sys.int::%%coerce-fixnum-to-float y)))
         (sys.int::%%float-- x y))
        (t (error "Unsupported argument combination."))))

(defun sys.int::generic-< (x y)
  (cond ((or (floatp x)
             (floatp y))
         (when (sys.int::fixnump x)
           (setf x (sys.int::%%coerce-fixnum-to-float x)))
         (when (sys.int::fixnump y)
           (setf y (sys.int::%%coerce-fixnum-to-float y)))
         (sys.int::%%float-< x y))
        (t (error "Unsupported argument combination."))))

(defun sys.int::generic-> (x y)
  (sys.int::generic-< y x))

(defun sys.int::generic-<= (x y)
  (not (sys.int::generic-< y x)))

(defun sys.int::generic->= (x y)
  (not (sys.int::generic-< x y)))

;;; From SBCL 1.0.55
(defun ceiling (number &optional (divisor 1))
  ;; If the numbers do not divide exactly and the result of
  ;; (/ NUMBER DIVISOR) would be positive then increment the quotient
  ;; and decrement the remainder by the divisor.
  (multiple-value-bind (tru rem) (truncate number divisor)
    (if (and (not (zerop rem))
             (if (minusp divisor)
                 (minusp number)
                 (plusp number)))
        (values (+ tru 1) (- rem divisor))
        (values tru rem))))

(defun integer-length (integer)
  (when (minusp integer) (setf integer (- integer)))
  (do ((len 0 (1+ len)))
      ((zerop integer)
       len)
    (setf integer (ash integer -1))))

(defun sys.int::raise-undefined-function (fref)
  (debug-write-string "Undefined function ")
  (let ((name (sys.int::%array-like-ref-t fref sys.int::+fref-name+)))
    (cond ((consp name)
           (debug-write-string "(")
           (debug-write-string (symbol-name (car name)))
           (debug-write-string " ")
           (debug-write-string (symbol-name (car (cdr name))))
           (debug-write-line ")"))
          (t (debug-write-line (symbol-name name)))))
  (sys.int::%sti)
  (loop))

(defun sys.int::raise-unbound-error (symbol)
  (debug-write-string "Unbound symbol ")
  (debug-write-line (symbol-name symbol))
  (sys.int::%sti)
  (loop))

(defun endp (list)
  (null list))

(defun cons (car cdr)
  (sys.int::cons-in-area car cdr nil))

(defun list (&rest objects)
  objects)

(defvar sys.int::*active-catch-handlers*)
(defun sys.int::%catch (tag fn)
  ;; Catch is used in low levelish code, so must avoid allocation.
  (let ((vec (sys.c::make-dx-simple-vector 3)))
    (setf (svref vec 0) sys.int::*active-catch-handlers*
          (svref vec 1) tag
          (svref vec 2) (flet ((exit-fn (values)
                                 (return-from sys.int::%catch (values-list values))))
                          (declare (dynamic-extent (function exit-fn)))
                          #'exit-fn))
    (let ((sys.int::*active-catch-handlers* vec))
      (funcall fn))))

(defun sys.int::%throw (tag values)
  (do ((current sys.int::*active-catch-handlers* (svref current 0)))
      ((not current)
       (error 'bad-catch-tag-error :tag tag))
    (when (eq (svref current 1) tag)
      (funcall (svref current 2) values))))

(defvar *tls-lock*)
(defvar sys.int::*next-symbol-tls-slot*)
(defconstant +maximum-tls-slot+ (1+ +thread-tls-slots-end+))
(defun sys.int::%allocate-tls-slot (symbol)
  (with-symbol-spinlock (*tls-lock*)
    ;; Make sure that another thread didn't allocate a slot while we were waiting for the lock.
    (cond ((zerop (ldb (byte 16 10) (sys.int::%array-like-ref-unsigned-byte-64 symbol -1)))
           (when (>= sys.int::*next-symbol-tls-slot* +maximum-tls-slot+)
             (error "Critial error! TLS slots exhausted!"))
           (let ((slot sys.int::*next-symbol-tls-slot*))
             (incf sys.int::*next-symbol-tls-slot*)
             ;; Twiddle TLS bits directly in the symbol header.
             (setf (ldb (byte 16 10) (sys.int::%array-like-ref-unsigned-byte-64 symbol -1)) slot)
             slot))
          (t (ldb (byte 16 10) (sys.int::%array-like-ref-unsigned-byte-64 symbol -1))))))

sys.int::(define-lap-function values-list ()
  (sys.lap-x86:push :rbp)
  (:gc :no-frame :layout #*0)
  (sys.lap-x86:mov64 :rbp :rsp)
  (:gc :frame)
  (sys.lap-x86:sub64 :rsp 16) ; 2 slots
  (sys.lap-x86:cmp32 :ecx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  (sys.lap-x86:jne bad-arguments)
  ;; RBX = iterator, (:stack 0) = list.
  (sys.lap-x86:mov64 :rbx :r8)
  (sys.lap-x86:mov64 (:stack 0) :r8)
  (:gc :frame :layout #*10)
  ;; ECX = value count.
  (sys.lap-x86:xor32 :ecx :ecx)
  ;; Pop into R8.
  ;; If LIST is NIL, then R8 must be NIL, so no need to
  ;; set R8 to NIL in the 0-values case.
  (sys.lap-x86:cmp64 :rbx nil)
  (sys.lap-x86:je done)
  (sys.lap-x86:mov8 :al :bl)
  (sys.lap-x86:and8 :al #b1111)
  (sys.lap-x86:cmp8 :al #.+tag-cons+)
  (sys.lap-x86:jne type-error)
  (sys.lap-x86:mov64 :r8 (:car :rbx))
  (sys.lap-x86:mov64 :rbx (:cdr :rbx))
  (sys.lap-x86:add64 :rcx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  ;; Pop into R9.
  (sys.lap-x86:cmp64 :rbx nil)
  (sys.lap-x86:je done)
  (sys.lap-x86:mov8 :al :bl)
  (sys.lap-x86:and8 :al #b1111)
  (sys.lap-x86:cmp8 :al #.+tag-cons+)
  (sys.lap-x86:jne type-error)
  (sys.lap-x86:mov64 :r9 (:car :rbx))
  (sys.lap-x86:mov64 :rbx (:cdr :rbx))
  (sys.lap-x86:add64 :rcx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  ;; Pop into R10.
  (sys.lap-x86:cmp64 :rbx nil)
  (sys.lap-x86:je done)
  (sys.lap-x86:mov8 :al :bl)
  (sys.lap-x86:and8 :al #b1111)
  (sys.lap-x86:cmp8 :al #.+tag-cons+)
  (sys.lap-x86:jne type-error)
  (sys.lap-x86:mov64 :r10 (:car :rbx))
  (sys.lap-x86:mov64 :rbx (:cdr :rbx))
  (sys.lap-x86:add64 :rcx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  ;; Pop into R11.
  (sys.lap-x86:cmp64 :rbx nil)
  (sys.lap-x86:je done)
  (sys.lap-x86:mov8 :al :bl)
  (sys.lap-x86:and8 :al #b1111)
  (sys.lap-x86:cmp8 :al #.+tag-cons+)
  (sys.lap-x86:jne type-error)
  (sys.lap-x86:mov64 :r11 (:car :rbx))
  (sys.lap-x86:mov64 :rbx (:cdr :rbx))
  (sys.lap-x86:add64 :rcx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  ;; Pop into R12.
  (sys.lap-x86:cmp64 :rbx nil)
  (sys.lap-x86:je done)
  (sys.lap-x86:mov8 :al :bl)
  (sys.lap-x86:and8 :al #b1111)
  (sys.lap-x86:cmp8 :al #.+tag-cons+)
  (sys.lap-x86:jne type-error)
  (sys.lap-x86:mov64 :r12 (:car :rbx))
  (sys.lap-x86:mov64 :rbx (:cdr :rbx))
  (sys.lap-x86:add64 :rcx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  ;; Registers are populated, now unpack into the MV-area
  (sys.lap-x86:mov32 :edi #.(+ (- 8 +tag-object+)
                               (* mezzanine.supervisor::+thread-mv-slots-start+ 8)))
  (:gc :frame :layout #*10 :multiple-values 0)
  unpack-loop
  (sys.lap-x86:cmp64 :rbx nil)
  (sys.lap-x86:je done)
  (sys.lap-x86:mov8 :al :bl)
  (sys.lap-x86:and8 :al #b1111)
  (sys.lap-x86:cmp8 :al #.+tag-cons+)
  (sys.lap-x86:jne type-error)
  (sys.lap-x86:cmp32 :ecx #.(ash (+ (- mezzanine.supervisor::+thread-mv-slots-end+ mezzanine.supervisor::+thread-mv-slots-start+) 5) +n-fixnum-bits+))
  (sys.lap-x86:jae too-many-values)
  (sys.lap-x86:mov64 :r13 (:car :rbx))
  (sys.lap-x86:mov64 :rbx (:cdr :rbx))
  (sys.lap-x86:gs)
  (sys.lap-x86:mov64 (:rdi) :r13)
  (:gc :frame :layout #*10 :multiple-values 1)
  (sys.lap-x86:add64 :rcx #.(ash 1 +n-fixnum-bits+)) ; fixnum 1
  (:gc :frame :layout #*10 :multiple-values 0)
  (sys.lap-x86:add64 :rdi 8)
  (sys.lap-x86:jmp unpack-loop)
  done
  (sys.lap-x86:leave)
  (:gc :no-frame :multiple-values 0)
  (sys.lap-x86:ret)
  type-error
  (:gc :frame :layout #*10)
  (sys.lap-x86:mov64 :r8 (:stack 0))
  (sys.lap-x86:mov64 :r9 (:constant proper-list))
  (sys.lap-x86:mov64 :r13 (:function raise-type-error))
  (sys.lap-x86:mov32 :ecx #.(ash 2 +n-fixnum-bits+)) ; fixnum 2
  (sys.lap-x86:call (:r13 #.(+ (- sys.int::+tag-object+) 8 (* sys.int::+fref-entry-point+ 8))))
  (sys.lap-x86:ud2)
  too-many-values
  (sys.lap-x86:mov64 :r8 (:constant "Too many values in list ~S."))
  (sys.lap-x86:mov64 :r9 (:stack 0))
  (sys.lap-x86:mov64 :r13 (:function error))
  (sys.lap-x86:mov32 :ecx #.(ash 2 +n-fixnum-bits+)) ; fixnum 2
  (sys.lap-x86:call (:r13 #.(+ (- sys.int::+tag-object+) 8 (* sys.int::+fref-entry-point+ 8))))
  (sys.lap-x86:ud2)
  bad-arguments
  (:gc :frame)
  (sys.lap-x86:mov64 :r13 (:function sys.int::%invalid-argument-error))
  (sys.lap-x86:call (:r13 #.(+ (- sys.int::+tag-object+) 8 (* sys.int::+fref-entry-point+ 8))))
  (sys.lap-x86:ud2))

sys.int::(defun %%unwind-to (target-special-stack-pointer)
  (declare (suppress-ssp-checking))
  (loop (when (eq target-special-stack-pointer (%%special-stack-pointer))
          (return))
     (assert (%%special-stack-pointer))
     (etypecase (svref (%%special-stack-pointer) 1)
       (symbol
        (%%unbind))
       (simple-vector
        (%%disestablish-block-or-tagbody))
       (function
        (%%disestablish-unwind-protect)))))

;;; <<<<<<

(defvar *boot-information-page*)

(defstruct (disk
             (:area :wired))
  device
  n-sectors
  sector-size
  max-transfer
  read-fn
  write-fn)

(defvar *disks*)

(defstruct (store-extent
             (:area :wired))
  store-base
  virtual-base
  size
  wired-p
  type
  zero-fill)

(defvar *paging-disk*)
(defvar *extent-table*)

(defconstant +n-physical-buddy-bins+ 32)
(defconstant +buddy-bin-size+ 16)

(defconstant +boot-information-boot-uuid-offset+ 0)
(defconstant +boot-information-physical-buddy-bins-offset+ 16)

(defun boot-uuid (offset)
  (check-type offset (integer 0 15))
  (sys.int::memref-unsigned-byte-8 *boot-information-page* offset))

(defun register-disk (device n-sectors sector-size max-transfer read-fn write-fn)
  (when (> sector-size +4k-page-size+)
    (debug-write-line "Ignoring device with sector size larger than 4k."))
  (let* ((disk (make-disk :device device
                          :sector-size sector-size
                          :n-sectors n-sectors
                          :max-transfer max-transfer
                          :read-fn read-fn
                          :write-fn write-fn))
         (page (or (allocate-physical-pages (ceiling (max +4k-page-size+ sector-size) +4k-page-size+))
                   ;; I guess this could happen on strange devices with sector sizes > 4k.
                   (error "Unable to allocate memory when examining device ~S!" device)))
         (page-addr (+ +physical-map-base+ (* page +4k-page-size+))))
    (setf *disks* (sys.int::cons-in-area disk *disks* :wired))
    ;; Read first 4k, figure out what to do with it.
    (or (funcall read-fn device 0 (ceiling +4k-page-size+ sector-size) page-addr)
        (progn
          (release-physical-pages page (ceiling (max +4k-page-size+ sector-size) +4k-page-size+))
          (error "Unable to read first sector on device ~S!" device)))
    ;; Search for a Mezzanine header here.
    ;; TODO: Scan for partition maps.
    (when (and
           (not *paging-disk*)
           ;; Match magic.
           (loop
              for byte in '(#x00 #x4D #x65 #x7A #x7A #x61 #x6E #x69 #x6E #x65 #x49 #x6D #x61 #x67 #x65 #x00)
              for offset from 0
              do (when (not (eql (sys.int::memref-unsigned-byte-8 page-addr offset) byte))
                   (return nil))
              finally (return t))
           ;; Match boot UUID.
           (loop
              for offset from 0 below 16
              do (when (not (eql (sys.int::memref-unsigned-byte-8 page-addr (+ 16 offset))
                                 (boot-uuid offset)))
                   (return nil))
              finally (return t)))
      (debug-write-line "Found boot image!")
      (setf *paging-disk* disk)
      ;; Initialize the extent table.
      (setf *extent-table* '())
      (dotimes (i (sys.int::memref-unsigned-byte-32 (+ page-addr 36) 0))
        (let* ((addr (+ page-addr 96 (* i 32)))
               (flags (sys.int::memref-unsigned-byte-64 addr 3)))
          (setf *extent-table*
                (sys.int::cons-in-area
                 (make-store-extent :store-base (sys.int::memref-unsigned-byte-64 addr 0)
                                    :virtual-base (sys.int::memref-unsigned-byte-64 addr 1)
                                    :size (sys.int::memref-unsigned-byte-64 addr 2)
                                    :wired-p (logbitp 3 flags)
                                    :type (ecase (ldb (byte 3 0) flags)
                                            (0 :pinned)
                                            (1 :pinned-2g)
                                            (2 :dynamic)
                                            (3 :dynamic-cons)
                                            (4 :nursery)
                                            (5 :stack)))
                 *extent-table*
                 :wired)))))
    ;; Release the pages.
    (release-physical-pages page (ceiling (max +4k-page-size+ sector-size) +4k-page-size+))))

(defvar *vm-lock*)

(defconstant +page-table-present+        #x001)
(defconstant +page-table-write+          #x002)
(defconstant +page-table-user+           #x004)
(defconstant +page-table-write-through+  #x008)
(defconstant +page-table-cache-disabled+ #x010)
(defconstant +page-table-accessed+       #x020)
(defconstant +page-table-dirty+          #x040)
(defconstant +page-table-page-size+      #x080)
(defconstant +page-table-global+         #x100)
(defconstant +page-table-address-mask+   #x000FFFFFFFFFF000)

(defun wait-for-page-via-interrupt (interrupt-frame extent address)
  (declare (ignore interrupt-frame))
  (with-mutex (*vm-lock*)
    ;; Examine the page table, if there's a present entry then the page
    ;; was mapped while acquiring the VM lock. Just return.
    (let ((cr3 (+ +physical-map-base+ (logand (sys.int::%cr3) (lognot #xFFF))))
          (pml4e (ldb (byte 9 39) address))
          (pdpe (ldb (byte 9 30) address))
          (pde (ldb (byte 9 21) address))
          (pte (ldb (byte 9 12) address)))
      (when (not (logtest +page-table-present+ (sys.int::memref-unsigned-byte-64 cr3 pml4e)))
        ;; No PDP. Allocate one.
        (let* ((frame (or (allocate-physical-pages 1)
                          (progn (debug-write-line "Aiee. No memory.")
                                 (loop))))
               (addr (+ +physical-map-base+ (ash frame 12))))
          (dotimes (i 512)
            (setf (sys.int::memref-unsigned-byte-64 addr i) 0))
          (setf (sys.int::memref-unsigned-byte-64 cr3 pml4e) (logior (ash frame 12)
                                                                     +page-table-present+
                                                                     +page-table-write+))))
      (let ((pdp (+ +physical-map-base+ (logand (sys.int::memref-unsigned-byte-64 cr3 pml4e) +page-table-address-mask+))))
        (when (not (logtest +page-table-present+ (sys.int::memref-unsigned-byte-64 pdp pdpe)))
          ;; No PDir. Allocate one.
          (let* ((frame (or (allocate-physical-pages 1)
                            (progn (debug-write-line "Aiee. No memory.")
                                   (loop))))
                 (addr (+ +physical-map-base+ (ash frame 12))))
            (dotimes (i 512)
              (setf (sys.int::memref-unsigned-byte-64 addr i) 0))
            (setf (sys.int::memref-unsigned-byte-64 pdp pdpe) (logior (ash frame 12)
                                                                      +page-table-present+
                                                                      +page-table-write+))))
        (let ((pdir (+ +physical-map-base+ (logand (sys.int::memref-unsigned-byte-64 pdp pdpe) +page-table-address-mask+))))
          (when (not (logtest +page-table-present+ (sys.int::memref-unsigned-byte-64 pdir pde)))
            ;; No PT. Allocate one.
            (let* ((frame (or (allocate-physical-pages 1)
                              (progn (debug-write-line "Aiee. No memory.")
                                     (loop))))
                   (addr (+ +physical-map-base+ (ash frame 12))))
              (dotimes (i 512)
                (setf (sys.int::memref-unsigned-byte-64 addr i) 0))
              (setf (sys.int::memref-unsigned-byte-64 pdir pde) (logior (ash frame 12)
                                                                        +page-table-present+
                                                                        +page-table-write+))))
          (let ((pt (+ +physical-map-base+ (logand (sys.int::memref-unsigned-byte-64 pdir pde) +page-table-address-mask+))))
            (when (not (logtest +page-table-present+ (sys.int::memref-unsigned-byte-64 pt pte)))
              ;; No page allocated. Allocate a page and read the data.
              (let* ((frame (or (allocate-physical-pages 1)
                                (progn (debug-write-line "Aiee. No memory.")
                                       (loop))))
                     (addr (+ +physical-map-base+ (ash frame 12))))
                (cond ((store-extent-zero-fill extent)
                       (dotimes (i 512)
                         (setf (sys.int::memref-unsigned-byte-64 addr i) 0)))
                      (t (debug-write-line "Reading page...")
                         (or (funcall (disk-read-fn *paging-disk*)
                                      (disk-device *paging-disk*)
                                      (* (truncate (+ (store-extent-store-base extent)
                                                      (- address (store-extent-virtual-base extent)))
                                                   +4k-page-size+)
                                         (ceiling +4k-page-size+ (disk-sector-size *paging-disk*)))
                                      (ceiling +4k-page-size+ (disk-sector-size *paging-disk*))
                                      addr)
                             (progn (debug-write-line "Unable to read page from disk")
                                    (loop)))))
                (setf (sys.int::memref-unsigned-byte-64 pt pte) (logior (ash frame 12)
                                                                        +page-table-present+
                                                                        +page-table-write+))))))))))

(defun sys.int::bootloader-entry-point (boot-information-page)
  (initialize-initial-thread)
  (setf *boot-information-page* boot-information-page)
  ;; FIXME: Should be done by cold generator
  (setf *allocator-lock* :unlocked
        *tls-lock* :unlocked
        sys.int::*active-catch-handlers* 'nil)
  (initialize-interrupts)
  (initialize-i8259)
  (initialize-physical-allocator)
  (initialize-threads)
  (when (not (boundp '*vm-lock*))
    (setf *vm-lock* (make-mutex "Global VM Lock")))
  (sys.int::%sti)
  (initialize-debug-serial #x3F8 4 38400)
  ;;(debug-set-output-pesudostream (lambda (op &optional arg) (declare (ignore op arg))))
  (debug-write-line "Hello, Debug World!")
  (setf *disks* '()
        *paging-disk* nil)
  (initialize-ata)
  (when (not *paging-disk*)
    (debug-write-line "Could not find boot device. Sorry.")
    (loop))
  ;; Load the extent table.
  (make-thread #'sys.int::initialize-lisp :name "Main thread")
  (finish-initial-thread))
