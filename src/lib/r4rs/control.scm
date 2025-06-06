(##include-once "./bool.scm")
(##include-once "./types.scm")
(##include-once "./pair-list.scm")

;; import apply primitives from host/<host>/lib/prim-apply.scm
(cond-expand
  ((host rvm)
   ;; Skip rvm host (spitting out the ribn)
   (begin))
  (else
    (##include-once (ribbit "prim-apply"))))


;; Control features (R4RS section 6.9).

;; (define (apply f arg1 . args) (##apply f (append (list arg1) args))))
(define (apply f args) (##apply f args))

(define (make-procedure code env) (##rib code env procedure-type))
(define (procedure-code x) (##field0 x))
(define (procedure-env x) (##field1 x))


(define (##map proc lst)
  (if (pair? lst)
    (cons (proc (##field0 lst)) (##map proc (##field1 lst)))
    '()))

(define (map proc . lsts)
  (if (pair? (##field0 lsts))
    (cons (apply proc (##map car lsts))
          (apply map (append (list proc) (##map cdr lsts))))
    '()))


(define (for-each proc . lsts)
  (if (pair? (##field0 lsts))
      (begin
        (apply proc (##map car lsts))
        (apply for-each (append (list proc) (##map cdr lsts))))
      #f))


;; First-class continuations.

(define (call/cc receiver)
  (let ((c (##field1 (##field1 (##close #f))))) ;; get call/cc continuation rib
    (receiver (lambda (r)
                (let ((c2 (##field1 (##field1 (##close #f)))))
                  (##field0-set! c2 (##field0 c)) ;; set "stack" field
                  (##field2-set! c2 (##field2 c)) ;; set "pc" field
                  r))))) ;; return to continuation

(define call-with-current-continuation call/cc)


;; ---------------------- UTILS NOT IN R4RS ---------------------- ;;

(define (find predicate lst)
  (if (pair? lst)
    (if (predicate (car lst))
      (car lst)
      (find predicate (cdr lst)))
    #f))

(define (filter predicate lst)
  (let loop ((lst lst) (acc '()))
    (if (pair? lst)
      (loop (cdr lst) (if (predicate (car lst)) 
                        (cons (car lst) acc) 
                        acc))
      (reverse acc))))

(define (compose f g)
  (lambda args (f (apply g args))))

;; FIXME: Remove and change the procs that depend on it
(define (##fold func base lst)
  (if (pair? lst)
    (##fold func (func base (##field0 lst)) (##field1 lst))
    base))

(define (fold func base lst)
  (if (pair? lst)
    (fold func (func (##field0 lst) base) (##field1 lst))
    base))

(define (fold-until func base lst (stop-value '()))
  (if (and (pair? lst) (not (equal? base stop-value)))
    (fold-until func (func (car lst)) (cdr lst) stop-value)
    base))

(define (scan func base state lst)
  (if (pair? lst)
    (scan func (car lst) (func base (car lst)) (cdr lst))
    state))

(define (scan-until func base state lst (stop-value '()))
  (if (and (pair? lst) (not (equal? state stop-value)))
    (scan-until func (##field0 lst) (func base (##field0 lst)) (##field1 lst) stop-value)
    state))

(define (##scan-until-false func base state lst)
  (if (and (pair? lst) state)
    (##scan-until-false func (##field0 lst) (func base (##field0 lst)) (##field1 lst))
    state))

(define (all pred lst)
  (if (pair? lst)
    (and (pred (##field0 lst)) (all pred (##field1 lst)))
    #t))

(define (partial f . args)
  (lambda other-args (apply f (append args other-args))))

