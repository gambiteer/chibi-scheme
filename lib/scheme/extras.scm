
(define (read-sexps file . o)
  (let ((in (open-input-file file)))
    (if (and (pair? o) (car o))
        (set-port-fold-case! in #t))
    (let lp ((res '()))
      (let ((x (read in)))
        (if (eof-object? x)
            (reverse res)
            (lp (cons x res)))))))

(define current-includes
  '())

(define-syntax push-includes!
  (er-macro-transformer
   (lambda (expr rename compare)
     (set! current-includes (cons (cadr expr) current-includes))
     #f)))

(define-syntax pop-includes!
  (er-macro-transformer
   (lambda (expr rename compare)
     (set! current-includes (cdr current-includes))
     #f)))

(define-syntax include/aux
  (er-macro-transformer
   (lambda (expr rename compare)
     (let ((ci? (cadr expr)))
       (let lp ((files (cddr expr)) (res '()))
         (cond
          ((null? files)
           (cons (rename 'begin) (reverse res)))
          ((not (string? (car files)))
           (error "include requires a string"))
          ((member (car files) current-includes)
           (error "recursive include" (car files)))
          (else
           (let ((includes current-includes))
             (lp (cdr files)
                 (cons `(,(rename 'begin)
                         (,(rename 'push-includes!) ,(car files))
                         ,@(read-sexps (car files) ci?)
                         (,(rename 'pop-includes!)))
                       res))))))))))

(define-syntax include
  (syntax-rules ()
    ((include file ...)
     (include/aux #f file ...))))

(define-syntax include-ci
  (syntax-rules ()
    ((include file ...)
     (include/aux #t file ...))))

(define (read-error? x)
  (and (error-object? x) (memq (exception-kind x) '(read read-incomplete)) #t))

(define (file-error? x)
  (and (error-object? x) (eq? 'file (exception-kind x))))

(define (features) *features*)

(define exact inexact->exact)
(define inexact exact->inexact)

(define (boolean=? x y . o)
  (if (not (boolean? x))
      (error "not a boolean" x)
      (and (eq? x y) (if (pair? o) (apply boolean=? y o) #t))))
(define (symbol=? x y . o)
  (if (not (symbol? x))
      (error "not a symbol" x)
      (and (eq? x y) (if (pair? o) (apply symbol=? y o) #t))))

(define call/cc call-with-current-continuation)

(define truncate-quotient quotient)
(define truncate-remainder remainder)
(define (truncate/ n m)
  (values (truncate-quotient n m) (truncate-remainder n m)))

(define (floor-quotient n m)
  (let ((res (floor (/ n m))))
    (if (and (exact? n) (exact? m))
        (inexact->exact res)
        res)))
(define (floor-remainder n m)
  (- n (* m (floor-quotient n m))))
(define (floor/ n m)
  (values (floor-quotient n m) (floor-remainder n m)))

(define (exact-integer-sqrt x)
  (let ((res (exact-sqrt x)))
    (values (car res) (cdr res))))

;; Adapted from Bawden's algorithm.
(define (rationalize x e)
  (define (sr x y return)
    (let ((fx (floor x)) (fy (floor y)))
      (cond
       ((>= fx x)
        (return fx 1))
       ((= fx fy)
        (sr (/ (- y fy)) (/ (- x fx)) (lambda (n d) (return (+ d (* fx n)) n))))
       (else
        (return (+ fx 1) 1)))))
  (let ((return (if (negative? x) (lambda (num den) (/ (- num) den)) /))
        (x (abs x))
        (e (abs e)))
    (sr (- x e) (+ x e) return)))

(define (square x) (* x x))

(define flush-output-port flush-output)

(define input-port-open? port-open?)
(define output-port-open? port-open?)

(define (close-port port)
  ((if (input-port? port) close-input-port close-output-port) port))

(define (u8-ready? port) (char-ready? port))

(define (call-with-port port proc)
  (let ((res (proc port)))
    (close-port port)
    res))

(define (eof-object) (read-char (open-input-string "")))

(define (read-bytevector n . o)
  (if (zero? n)
      #u8()
      (let* ((in (if (pair? o) (car o) (current-input-port)))
             (vec (make-bytevector n))
             (res (read-bytevector! vec in)))
        (cond ((eof-object? res) res)
              ((< res n) (subbytes vec 0 res))
              (else vec)))))

(define (read-bytevector! vec . o)
  (let* ((in (if (pair? o) (car o) (current-input-port)))
         (o (if (pair? o) (cdr o) o))
         (start (if (pair? o) (car o) 0))
         (end (if (and (pair? o) (pair? (cdr o)))
                  (cadr o)
                  (bytevector-length vec)))
         (n (- end start)))
    (if (>= start end)
        0
        (let lp ((i 0))
          (if (>= i n)
              i
              (let ((x (read-u8 in)))
                (cond ((eof-object? x)
                       (if (zero? i) x i))
                      (else
                       (bytevector-u8-set! vec (+ i start) x)
                       (lp (+ i 1))))))))))

(define (write-bytevector vec . o)
  (let* ((out (if (pair? o) (car o) (current-output-port)))
         (o (if (pair? o) (cdr o) '()))
         (start (if (pair? o) (car o) 0))
         (o (if (pair? o) (cdr o) '()))
         (end (if (pair? o) (car o) (bytevector-length vec))))
    (do ((i start (+ i 1)))
        ((>= i end))
      (write-u8 (bytevector-u8-ref vec i) out))))

(define (list-set! ls k x)
  (cond ((null? ls) (error "invalid list index"))
        ((zero? k) (set-car! ls x))
        (else (list-set! (cdr ls) (- k 1) x))))

(define (vector-append . vecs)
  (let* ((len (apply + (map vector-length vecs)))
         (res (make-vector len)))
    (let lp ((ls vecs) (i 0))
      (if (null? ls)
          res
          (let ((v-len (vector-length (car ls))))
            (vector-copy! res i (car ls))
            (lp (cdr ls) (+ i v-len)))))))

(define (vector-map proc vec . lov)
  (cond
   ((null? lov)
    (let lp ((i (vector-length vec)) (res '()))
      (if (zero? i)
          (list->vector res)
          (lp (- i 1) (cons (proc (vector-ref vec (- i 1))) res)))))
   ((null? (cdr lov))
    (let ((vec2 (car lov)))
      (let lp ((i (vector-length vec)) (res '()))
        (if (zero? i)
            (list->vector res)
            (lp (- i 1)
                (cons (proc (vector-ref vec (- i 1)) (vector-ref vec2 (- i 1)))
                      res))))))
   (else
    (list->vector (apply map proc (map vector->list (cons vec lov)))))))

(define (vector-for-each proc vec . lov)
  (if (null? lov)
      (let ((len (vector-length vec)))
        (let lp ((i 0))
          (cond ((< i len)
                 (proc (vector-ref vec i))
                 (lp (+ i 1))))))
      (apply for-each proc (map vector->list (cons vec lov)))))

(define (vector-copy! to at from . o)
  (let* ((start (if (pair? o) (car o) 0))
         (end (if (and (pair? o) (pair? (cdr o))) (cadr o) (vector-length from)))
         (limit (min end (+ start (- (vector-length to) at)))))
    (if (<= at start)
        (do ((i at (+ i 1)) (j start (+ j 1)))
            ((>= j limit))
          (vector-set! to i (vector-ref from j)))
        (do ((i (+ at (- end start 1)) (- i 1)) (j (- limit 1) (- j 1)))
            ((< j start))
          (vector-set! to i (vector-ref from j))))))

(define (vector->string vec . o)
  (list->string (apply vector->list vec o)))

(define (string->vector vec . o)
  (list->vector (apply string->list vec o)))

(define (bytevector . args)
  (let* ((len (length args))
         (res (make-bytevector len)))
    (do ((i 0 (+ i 1)) (ls args (cdr ls)))
        ((null? ls) res)
      (bytevector-u8-set! res i (car ls)))))

(define (bytevector-copy! to at from . o)
  (let* ((start (if (pair? o) (car o) 0))
         (end (if (and (pair? o) (pair? (cdr o)))
                  (cadr o)
                  (bytevector-length from)))
         (limit (min end (+ start (- (bytevector-length to) at)))))
    (if (<= at start)
        (do ((i at (+ i 1)) (j start (+ j 1)))
            ((>= j limit))
          (bytevector-u8-set! to i (bytevector-u8-ref from j)))
        (do ((i (+ at (- end start 1)) (- i 1)) (j (- limit 1) (- j 1)))
            ((< j start))
          (bytevector-u8-set! to i (bytevector-u8-ref from j))))))

(define (bytevector-copy vec . o)
  (if (null? o)
      (subbytes vec 0)
      (apply subbytes vec o)))

(define (bytevector-append . vecs)
  (let* ((len (apply + (map bytevector-length vecs)))
         (res (make-bytevector len)))
    (let lp ((ls vecs) (i 0))
      (if (null? ls)
          res
          (let ((v-len (bytevector-length (car ls))))
            (bytevector-copy! res i (car ls))
            (lp (cdr ls) (+ i v-len)))))))

;; Never use this!
(define (string-copy! to at from . o)
  (let* ((start (if (pair? o) (car o) 0))
         (end (if (and (pair? o) (pair? (cdr o))) (cadr o) (string-length from)))
         (limit (min end (+ start (- (string-length to) at)))))
    (if (<= at start)
        (do ((i at (+ i 1)) (j start (+ j 1)))
            ((>= j limit))
          (string-set! to i (string-ref from j)))
        (do ((i (+ at (- end start 1)) (- i 1)) (j (- limit 1) (- j 1)))
            ((< j start))
          (string-set! to i (string-ref from j))))))

(define truncate-quotient quotient)
(define truncate-remainder remainder)
(define (truncate/ n m)
  (values (truncate-quotient n m) (truncate-remainder n m)))

(cond-expand
 (ratios
  (define (floor-quotient n m)
    (floor (/ n m))))
 (else
  (define (floor-quotient n m)
    (let ((res (floor (/ n m))))
      (if (and (exact? n) (exact? m))
          (exact res)
          res)))))
(define (floor-remainder n m)
  (- n (* m (floor-quotient n m))))
(define (floor/ n m)
  (values (floor-quotient n m) (floor-remainder n m)))
