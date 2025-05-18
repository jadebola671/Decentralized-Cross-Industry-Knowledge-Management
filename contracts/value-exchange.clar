;; Value Exchange Contract
;; Handles compensation for access to knowledge assets

(define-data-var admin principal tx-sender)

;; Payment counter
(define-data-var payment-counter uint u0)

;; Map to store payment records
(define-map payment-records uint
  {
    asset-id: uint,
    payer: principal,
    recipient: principal,
    amount: uint,
    timestamp: uint,
    status: (string-utf8 20),  ;; "pending", "completed", "refunded"
    access-id: uint
  }
)

;; Map to track payments by asset
(define-map asset-payments uint (list 50 uint))

;; Map to track payments by user (as payer)
(define-map user-payments principal (list 50 uint))

;; Map to track earnings by user (as recipient)
(define-map user-earnings principal (list 50 uint))

;; Map of payments: {asset-id, payer} -> amount
(define-map payments
  { asset-id: uint, payer: principal }
  uint
)

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_NOT_FOUND u2)
(define-constant ERR_INSUFFICIENT_FUNDS u3)
(define-constant ERR_INVALID_STATUS u4)
(define-constant err-unauthorized u1)
(define-constant err-insufficient-funds u2)

;; Make payment for asset access
(define-public (pay-for-access
                (asset-id uint)
                (access-type (string-utf8 20))
                (expiration uint)
                (knowledge-asset-contract principal)
                (access-control-contract principal))
  (let
    (
      (payment-id (var-get payment-counter))
      (asset (contract-call? knowledge-asset-contract get-asset asset-id))
    )

    (asserts! (is-some asset) (err ERR_NOT_FOUND))

    (let
      (
        (some-asset (unwrap-panic asset))
        (owner (get owner (unwrap-panic asset)))
        (asset-payments-list (default-to (list) (map-get? asset-payments asset-id)))
        (user-payments-list (default-to (list) (map-get? user-payments tx-sender)))
        (owner-earnings (default-to (list) (map-get? user-earnings owner)))
        ;; For simplicity, we're using a fixed amount
        (payment-amount u100)
      )

      ;; Check if user has enough funds (simplified)
      (asserts! (>= (stx-get-balance tx-sender) payment-amount) (err ERR_INSUFFICIENT_FUNDS))

      ;; Transfer STX from payer to recipient
      (try! (stx-transfer? payment-amount tx-sender owner))

      ;; Increment payment counter
      (var-set payment-counter (+ payment-id u1))

      ;; Grant access
      (try! (contract-call? access-control-contract grant-access
              asset-id
              tx-sender
              access-type
              expiration
              knowledge-asset-contract))

      ;; Store the payment record
      (map-set payment-records payment-id
        {
          asset-id: asset-id,
          payer: tx-sender,
          recipient: owner,
          amount: payment-amount,
          timestamp: block-height,
          status: "completed",
          access-id: u0  ;; Placeholder
        }
      )

      ;; Update asset payments list - fixed list append
      (let ((new-asset-payments (unwrap-panic (as-max-len? (append asset-payments-list payment-id) u50))))
        (map-set asset-payments asset-id new-asset-payments)
      )

      ;; Update user payments list - fixed list append
      (let ((new-user-payments (unwrap-panic (as-max-len? (append user-payments-list payment-id) u50))))
        (map-set user-payments tx-sender new-user-payments)
      )

      ;; Update owner earnings list - fixed list append
      (let ((new-owner-earnings (unwrap-panic (as-max-len? (append owner-earnings payment-id) u50))))
        (map-set user-earnings owner new-owner-earnings)
      )

      ;; Record the payment
      (map-set payments
        { asset-id: asset-id, payer: tx-sender }
        payment-amount
      )

      (ok payment-id)
    )
  )
)

;; Get payment record
(define-read-only (get-payment-record (payment-id uint))
  (map-get? payment-records payment-id)
)

;; Get all payments for an asset
(define-read-only (get-asset-payments (asset-id uint))
  (default-to (list) (map-get? asset-payments asset-id))
)

;; Get all payments made by a user
(define-read-only (get-user-payments (user principal))
  (default-to (list) (map-get? user-payments user))
)

;; Get all earnings received by a user
(define-read-only (get-user-earnings (user principal))
  (default-to (list) (map-get? user-earnings user))
)

;; Get payment amount
(define-read-only (get-payment (asset-id uint) (payer principal))
  (default-to u0 (map-get? payments { asset-id: asset-id, payer: payer }))
)

;; Refund a payment (admin only)
(define-public (refund-payment (payment-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err ERR_UNAUTHORIZED))

    (match (map-get? payment-records payment-id)
      payment (begin
        (asserts! (is-eq (get status payment) "completed") (err ERR_INVALID_STATUS))

        ;; Transfer STX back to payer
        (try! (stx-transfer? (get amount payment) (get recipient payment) (get payer payment)))

        ;; Update payment status
        (map-set payment-records payment-id
          (merge payment { status: "refunded" })
        )

        (ok true)
      )
      (err ERR_NOT_FOUND)
    )
  )
)
