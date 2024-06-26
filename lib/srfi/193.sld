
(define-library (srfi 193)
  (export command-line command-name command-args script-file script-directory)
  (import (scheme base) (chibi filesystem) (chibi pathname)
          (only (chibi) command-line)
          (only (meta) raw-script-file))
  (begin
    (define start-directory (current-directory))

    (define (command-name)
      (let ((filename (car (command-line))))
        (and (not (= 0 (string-length filename)))
             (path-strip-extension (path-strip-directory filename)))))

    (define (command-args)
      (cdr (command-line)))

    (define (script-file)
      (and raw-script-file
           (path-normalize
            (path-resolve raw-script-file start-directory))))

    (define (script-directory)
      (let ((filename (script-file)))
        (and filename (string-append (path-directory filename) "/"))))))
