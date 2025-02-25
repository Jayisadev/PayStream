;; PayStream: A Subscription Token Smart Contract
;; This contract enables users to subscribe to services using tokens with a pay-as-you-go model.

(define-data-var contract-owner principal tx-sender)
(define-map subscriptions
  { user: principal }
  { 
    balance: uint,
    last-payment: uint,
    rate: uint,            ;; tokens consumed per block
    active: bool
  }
)
(define-map service-providers
  { provider: principal }
  { authorized: bool }
)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-SUBSCRIBED (err u101))
(define-constant ERR-NOT-SUBSCRIBED (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-NOT-PROVIDER (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-PRINCIPAL (err u106))

;; Admin functions

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    ;; Validate new owner is not null principal
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78)) ERR-INVALID-PRINCIPAL)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (authorize-provider (provider principal) (authorized bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    ;; Validate provider is not null principal
    (asserts! (not (is-eq provider 'SP000000000000000000002Q6VF78)) ERR-INVALID-PRINCIPAL)
    (map-set service-providers { provider: provider } { authorized: authorized })
    (ok true)
  )
)

;; Subscription management

(define-public (subscribe (rate uint))
  (let (
    (existing-subscription (map-get? subscriptions { user: tx-sender }))
  )
    (asserts! (> rate u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none existing-subscription) ERR-ALREADY-SUBSCRIBED)
    
    (map-set subscriptions 
      { user: tx-sender } 
      { 
        balance: u0,
        last-payment: stacks-block-height,
        rate: rate,
        active: false
      }
    )
    (ok true)
  )
)

(define-public (add-balance (amount uint))
  (let (
    (user-subscription (unwrap! (map-get? subscriptions { user: tx-sender }) ERR-NOT-SUBSCRIBED))
    (new-balance (+ (get balance user-subscription) amount))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (map-set subscriptions 
      { user: tx-sender } 
      (merge user-subscription { 
        balance: new-balance,
        active: true
      })
    )
    
    (ok new-balance)
  )
)

(define-public (cancel-subscription)
  (let (
    (user-subscription (unwrap! (map-get? subscriptions { user: tx-sender }) ERR-NOT-SUBSCRIBED))
  )
    (map-delete subscriptions { user: tx-sender })
    (ok (get balance user-subscription))
  )
)

;; Service provider functions

(define-public (check-subscription (user principal))
  (let (
    (provider-data (unwrap! (map-get? service-providers { provider: tx-sender }) ERR-NOT-PROVIDER))
    (subscription-data (unwrap! (map-get? subscriptions { user: user }) ERR-NOT-SUBSCRIBED))
  )
    ;; Validate user is not null principal
    (asserts! (not (is-eq user 'SP000000000000000000002Q6VF78)) ERR-INVALID-PRINCIPAL)
    ;; Validate provider is authorized
    (asserts! (get authorized provider-data) ERR-NOT-AUTHORIZED)
    ;; Validate subscription is active
    (asserts! (get active subscription-data) ERR-NOT-SUBSCRIBED)
    
    (let (
      (blocks-passed (- stacks-block-height (get last-payment subscription-data)))
      (consumed-tokens (* blocks-passed (get rate subscription-data)))
      (remaining-balance (get balance subscription-data))
    )
      (if (>= consumed-tokens remaining-balance)
        ;; If consumed more than balance, deactivate subscription
        (begin
          (map-set subscriptions
            { user: user }
            (merge subscription-data {
              balance: u0,
              last-payment: stacks-block-height,
              active: false
            })
          )
          (ok false)
        )
        ;; Otherwise, deduct from balance and continue
        (begin
          (map-set subscriptions
            { user: user }
            (merge subscription-data {
              balance: (- remaining-balance consumed-tokens),
              last-payment: stacks-block-height
            })
          )
          (ok true)
        )
      )
    )
  )
)

;; Read-only functions

(define-read-only (get-subscription-status (user principal))
  (let (
    (subscription (map-get? subscriptions { user: user }))
  )
    (if (is-some subscription)
      (let (
        (sub (unwrap-panic subscription))
        (blocks-passed (- stacks-block-height (get last-payment sub)))
        (consumed-tokens (* blocks-passed (get rate sub)))
        (remaining-balance (get balance sub))
      )
        (if (and (get active sub) (> remaining-balance consumed-tokens))
          (ok {
            active: true,
            remaining-balance: (- remaining-balance consumed-tokens),
            rate: (get rate sub)
          })
          (ok {
            active: false,
            remaining-balance: (get balance sub),
            rate: (get rate sub)
          })
        )
      )
      (err ERR-NOT-SUBSCRIBED)
    )
  )
)

(define-read-only (is-service-provider (provider principal))
  (default-to false (get authorized (map-get? service-providers { provider: provider })))
)