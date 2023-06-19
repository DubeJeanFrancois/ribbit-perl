(##include-once "./types.scm")
(##include-once "./pair-list.scm")
(##include-once "./error.scm")
(##include-once "./io.scm")
(##include-once "./qq.scm")
(##include-once "./control.scm")

(cond-expand
  ((host js)
   (define-primitive
     (welcome-msg)
     "() => (console.log(`
              ____________________
             |                    |
             | Welcome to Ribbit! |
             |                    |
    λ        | - Rib the Frog     |
  @...@  --- |____________________|
 (-----)
( >___< )
^^ ~~~ ^^`), true),")))

;; Compiler from Ribbit Scheme to RVM code.

(define jump/call-op 0)
(define set-op       1)
(define get-op       2)
(define const-op     3)
(define if-op        4)

(define (add-nb-args nb tail)
  (##rib const-op
       nb
       tail))

(define (improper-length lst)
  (if (pair? lst)
    (##+ 1 (improper-length (##field1 lst)))
    0))

(define (last-item lst)
  (if (pair? lst)
    (last-item (##field1 lst))
    lst))

(define (comp cte expr cont)
  (cond ((symbol? expr)
         (##rib get-op (lookup expr cte 0) cont))

        ((pair? expr)
         (let ((first (##field0 expr)))
           (cond ((##eqv? first 'quote)
                  (##rib const-op (cadr expr) cont))

                 ((##eqv? first 'quasiquote)
                  (comp cte
                        (expand-qq (cadr expr))
                        cont))

                 ((or (##eqv? first 'set!) (##eqv? first 'define))  ;; maybe replace with 'or
                  (comp cte
                        (caddr expr)
                        (gen-assign (lookup (cadr expr) cte 1)
                                    cont)))

                 ((##eqv? first 'if)
                  (comp cte
                        (cadr expr)
                        (##rib if-op
                             (comp cte (caddr expr) cont)
                             (comp cte (cadddr expr) cont))))

                 ((##eqv? first 'lambda)
                  (let* ((params (cadr expr)) 
                         (variadic (or (symbol? params) (not (null? (last-item params)))))
                         (nb-params (if variadic (##+ 1 (##* 2 (improper-length params))) (##* 2 (length params)))))
                    (##rib const-op
                         (make-procedure
                           (##rib nb-params
                                0
                                (comp-begin (extend params
                                                    (cons #f
                                                          (cons #f
                                                                cte)))
                                            (cddr expr)
                                            tail))
                           '())
                         (if (null? cte)
                           cont
                           (add-nb-args
                             1
                             (gen-call '##close cont))))))

                 ;#; ;; support for begin special form
                 ((##eqv? first 'begin)
                  (comp-begin cte (##field1 expr) cont))

                 ;#; ;; support for single armed let special form
                 ((##eqv? first 'let)
                  (let ((binding (caadr expr)))
                    (comp-bind cte
                               (##field0 binding)
                               (cadr binding)
                               ;;                               #; ;; support for single expression in body
                               ;;                               (caddr expr)
                               ;#; ;; support for multiple expressions in body
                               (cddr expr)
                               cont)))

                 ;#; ;; support for single armed let special form
                 ((##eqv? first 'letrec)
                  (let ((bindings (cadr expr)))
                    (comp cte
                          (cons 'let
                                (cons (map (lambda (binding)
                                             (list (##field0 binding) #f))
                                           bindings)
                                      (append (map (lambda (binding)
                                                     (list 'set! (##field0 binding) (cadr binding)))
                                                   bindings)
                                              (cddr expr))))
                          cont)))

                 ;#; ;; support for and special form
                 ((##eqv? first 'and)
                  (comp cte
                        (if (pair? (##field1 expr))
                          (let ((second (cadr expr)))
                            (if (pair? (cddr expr))
                              (build-if second
                                        (cons 'and (cddr expr))
                                        #f)
                              second))
                          #t)
                        cont))

                 ;#; ;; support for or special form
                 ((##eqv? first 'or)
                  (comp cte
                        (if (pair? (##field1 expr))
                          (let ((second (cadr expr)))
                            (if (pair? (cddr expr))
                              (list 'let
                                    (list (list '_ second))
                                    (build-if '_
                                              '_
                                              (cons 'or (cddr expr))))
                              second))
                          #f)
                        cont))

                 ;#; ;; support for cond special form
                 ((##eqv? first 'cond)
                  (comp cte
                        (if (pair? (##field1 expr))
                          (if (##eqv? 'else (caadr expr))
                            (cons 'begin (cdadr expr))
                            (build-if (caadr expr)
                                      (cons 'begin (cdadr expr))
                                      (cons 'cond (cddr expr))))
                          #f)
                        cont))

                 ((##eqv? first 'case)
                  (let ((key (##field0 (##field1 expr))))
                    (let ((clauses (##field1 (##field1 expr))))
                      (if (pair? clauses)
                        (let ((clause (##field0 clauses)))
                          (comp cte
                                (if (##eqv? (##field0 clause) 'else)
                                  (cons 'begin (##field1 clause))
                                  (build-if (list '##case-memv key (list 'quote (##field0 clause)))
                                            (cons 'begin (##field1 clause))
                                            (list 'case key (##field1 clauses))))))
                        #f))))

                 (else
                   ;;                  #; ;; support for calls with only variable in operator position
                   ;;                  (comp-call cte
                   ;;                             (##field1 expr)
                   ;;                             (cons first cont))
                   ;#; ;; support for calls with any expression in operator position
                   (let ((args (##field1 expr)))
                     (if (symbol? first)
                       (comp-call cte
                                  args
                                  (length args)
                                  (cons first cont))
                       (comp-bind cte
                                  '_
                                  first
                                  ;;                                   #; ;; support for single expression in body
                                  ;;                                   (cons '_ args)
                                  ;#; ;; support for multiple expressions in body
                                  (list (cons '_ args))
                                  cont)))))))

        (else
          ;; self-evaluating
          (##rib const-op expr cont))))

;#; ;; support for and, or, cond special forms
(define (build-if a b c) (cons 'if (list a b c)))

(define (expand-constant expr)
  (##qq-list 'quote expr))

(define (expand-qq expr)
  (let parse ((x expr) (depth 1))
    (cond 
      ((not (pair? x))
       (if (vector? x)
         (##qq-list '##qq-list->vector (parse (##qq-vector->list x) depth))
         (expand-constant x)))
      ((##eqv? (##field0 x) 'unquote)
       (if (##eqv? depth 1)
         (cadr x)
         (##qq-list '##qq-cons (expand-constant 'unquote) (parse (##field1 x) (- depth 1)))))
      ((and (pair? (##field0 x)) (##eqv? (caar x) 'unquote-splicing))
       (if (##eqv? depth 1)
         (##qq-list '##qq-append (cadar x) (parse (##field1 x) depth))
         (##qq-list '##qq-cons (##qq-list '##qq-cons (expand-constant 'unquote-splicing) (parse (cdar x) (- depth 1))) (parse (##field1 x) depth))))
      ((##eqv? (##field0 x) 'quasiquote)
       (##qq-list '##qq-cons (expand-constant 'quasiquote) (parse (##field1 x) (+ depth 1))))
      (else
        (##qq-list '##qq-cons (parse (##field0 x) depth) (parse (##field1 x) depth))))))

(define (comp-bind cte var expr body cont)
  (comp cte
        expr
;;        #; ;; support for single expression in body
;;        (comp (cons var cte)
;;              body
;;              (if (eqv? cont tail)
;;                  cont
;;                  (##rib jump/call-op ;; call
;;                       'arg2
;;                       cont)))
        ;#; ;; support for multiple expressions in body
        (comp-begin (cons var cte)
                    body
                    (if (##eqv? cont tail)
                        cont
                        (if-feature 
                          prim-no-arity
                          (##rib jump/call-op ;; call
                           '##arg2
                           cont)
                          (add-nb-args
                            2
                            (##rib jump/call-op ;; call
                             '##arg2
                             cont)))))))

(define (comp-begin cte exprs cont)
  (comp cte
        (##field0 exprs)
        (if (pair? (##field1 exprs))
          (if-feature 
            prim-no-arity
            (##rib jump/call-op ;; call
             '##arg1
             (comp-begin cte (##field1 exprs) cont))
            (add-nb-args
              2
              (##rib jump/call-op ;; call
               '##arg1
               (comp-begin cte (##field1 exprs) cont))))
            cont)))

(define (gen-call v cont)
  (if (##eqv? cont tail)
      (##rib jump/call-op v 0)      ;; jump
      (##rib jump/call-op v cont))) ;; call

(define (gen-assign v cont)
  (##rib set-op v 
       (if (and (##rib? cont) ;; starts with pop?
                (##eqv? (##field0 cont) jump/call-op) ;; call?
                (##eqv? (##field1 cont) '##arg1)
                (##rib? (##field2 cont)))
         (##field2 cont) ;; remove pop
         (##rib const-op 0 cont))))

;; (define (gen-noop cont)
;;   (if (and (rib? cont) ;; starts with pop?
;;            (eqv? (field0 cont) jump/call-op) ;; call?
;;            (eqv? (field1 cont) 'arg1)
;;            (rib? (field2 cont)))
;;       (field2 cont) ;; remove pop
;;       (##rib const-op 0 cont))) ;; add dummy value for set!

(define (comp-call cte exprs nb-args var-cont)
  (if (pair? exprs)
    (comp cte
          (##field0 exprs)
          (comp-call (cons #f cte)
                     (##field1 exprs)
                     nb-args
                     var-cont))
    (let ((var (##field0 var-cont)))
      (let ((cont (##field1 var-cont)))
        (let ((v (lookup var cte 0)))
          ;; should be unecessary because there shouldn't be any primitive called this way
          ;; (if-feature 
          ;;   prim-no-arity
          ;;   (if (##rib? (##field0 (##field0 var))) 
          ;;     (add-nb-args
          ;;       nb-args
          ;;       (gen-call (if (integer? v) (##+ 1 v) v) cont))
          ;;     (gen-call (if (integer? v) (##+ 1 v) v) cont))
            (add-nb-args
              nb-args
              (gen-call (if (integer? v) (##+ 1 v) v) cont)))))))

(define (lookup var cte i)
  (if (pair? cte)
      (if (##eqv? (##field0 cte) var)
          i
          (lookup var (##field1 cte) (##+ i 1)))
      var))

(define (extend vars cte)
  (if (pair? vars)
      (cons (##field0 vars) (extend (##field1 vars) cte))
      cte))

(define tail
  (if-feature 
    prim-no-arity
    (##rib jump/call-op '##id 0)
    (add-nb-args 1 (##rib jump/call-op '##id 0)))) ;; jump

;; (define (compile expr) ;; converts an s-expression to a procedure
;;   (let ((foo (comp '() expr tail)))
;;     (make-procedure (##rib 0 0 foo) '())))

(define (eval expr)
  ((make-procedure (##rib 0 0 (comp '() expr tail)) '())))

(define (##repl-inner)
  (display "> ")
  (let ((expr (read)))
    (if (eof-object? expr)
        (newline)
        (begin
          (write (eval expr))
          (newline)
          (##repl-inner)))))

(define (repl)
  (welcome-msg)
  (newline)
  (##repl-inner)
  (##exit 0))


;; ---------------------- LOAD ---------------------- ;;

(define (load filename)
  (let ((port (open-input-file filename)))
    (let loop ((expr (read port)))
      (if (eof-object? expr)
        (begin
          (close-input-port port)
          '())
        (begin
          (eval expr)
          (loop (read port)))))))

