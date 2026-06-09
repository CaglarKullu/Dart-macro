;; payment.sexp
;; Compile with: dart run bin/dmacro.dart compile payment.sexp -o payment.dart
;;
;; This is the actual source you write.
;; The .dart file is generated — never edit it directly.

;; ── Data model ───────────────────────────────────────────────────────────────
;; One declaration generates: fields, constructor, copyWith, ==, hashCode, toString
;; Compare to ~40 lines of Dart boilerplate or @freezed + build_runner

(defrecord Payment
  (double  amount)
  (String  currency)
  (String? reference))

(defrecord TransferRequest
  (Payment  payment)
  (String   fromAccount)
  (String   toAccount))

;; ── Validation ───────────────────────────────────────────────────────────────
;; assert-that embeds the expression source in the error message.
;; A regular Dart function receives `false` — it can never know what produced it.

(defn bool validatePayment ((double amount) (String currency))
  (unless (> amount 0)
    (throw (Exception "Amount must be positive")))
  (unless (!= currency "")
    (throw (Exception "Currency must not be empty")))
  (assert-that (<= amount 1000000))
  (assert-that (>= amount 0.01))
  (return true))

;; ── Processing with retry ────────────────────────────────────────────────────
;; with-retry generates a stateful for-loop with try/catch inline.
;; Impossible as a higher-order function because _attempt leaks into the body.

(defn void processPayment ((Payment payment) (String endpoint))
  (with-retry 3
    (postJson endpoint payment)))

;; ── Custom control flow ──────────────────────────────────────────────────────
;; unless and when are macros — zero runtime overhead, expand to plain if.

(defn String describeBalance ((double balance))
  (unless (>= balance 0)
    (return "overdrawn"))
  (when (> balance 10000)
    (return "high balance"))
  (return "normal"))

;; ── Swap values ──────────────────────────────────────────────────────────────
;; swap! injects a temp variable directly into the caller's scope.
;; A function cannot do this — it receives values, not variable names.

(defn void sortPair ((double a) (double b))
  (when (> a b)
    (swap! a b)))
