;; Entity Verification Contract
;; Simple registry of verified entities

;; Admin principal
(define-data-var admin principal tx-sender)

;; Map of verified entities: principal -> bool
(define-map verified-entities principal bool)

;; Error codes
(define-constant err-unauthorized u1)
(define-constant err-not-found u2)

;; Register an entity (admin only)
(define-public (register-entity (entity principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err err-unauthorized))
    (map-set verified-entities entity true)
    (ok true)
  )
)

;; Check if an entity is verified
(define-read-only (is-verified (entity principal))
  (default-to false (map-get? verified-entities entity))
)

;; Revoke verification (admin only)
(define-public (revoke-entity (entity principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err err-unauthorized))
    (map-set verified-entities entity false)
    (ok true)
  )
)

;; Transfer admin role (admin only)
(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err err-unauthorized))
    (var-set admin new-admin)
    (ok true)
  )
)
