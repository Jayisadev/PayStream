;; PayStream: A Subscription Token Smart Contract
;; This contract enables users to subscribe to services using tokens with a pay-as-you-go model.
;; Now with multi-tier subscription plans (Basic, Pro, Premium)

(define-data-var contract-owner principal tx-sender)
(define-map subscriptions
  { user: principal }
  { 
    balance: uint,
    last-payment: uint,
    rate: uint,            ;; tokens consumed per block
    active: bool,
    tier: (string-ascii 10)  ;; subscription tier (Basic, Pro, Premium)
  }
)
(define-map service-providers
  { provider: principal }
  { authorized: bool }
)

;; Define subscription tiers with their rates and features
(define-map subscription-tiers
  { tier-name: (string-ascii 10) }
  {
    rate: uint,              ;; base rate for this tier
    features: (list 10 (string-ascii 20))  ;; list of features available for this tier
  }
)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-SUBSCRIBED (err u101))
(define-constant ERR-NOT-SUBSCRIBED (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-NOT-PROVIDER (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-PRINCIPAL (err u106))
(define-constant ERR-INVALID-TIER (err u107))
(define-constant ERR-INVALID-FEATURES (err u108))

;; Private helper functions
(define-private (validate-tier-name (tier-name (string-ascii 10)))
  (or 
    (is-eq tier-name "Basic")
    (is-eq tier-name "Pro")
    (is-eq tier-name "Premium")
  )
)

(define-private (validate-features (features (list 10 (string-ascii 20))))
  (and
    (> (len features) u0)
    (<= (len features) u10)
  )
)

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

;; Tier management functions
(define-public (define-subscription-tier (tier-name (string-ascii 10)) (base-rate uint) (features (list 10 (string-ascii 20))))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (validate-tier-name tier-name) ERR-INVALID-TIER)
    (asserts! (> base-rate u0) ERR-INVALID-AMOUNT)
    (asserts! (validate-features features) ERR-INVALID-FEATURES)
    
    (let
      ((validated-features features))
      (map-set subscription-tiers
        { tier-name: tier-name }
        {
          rate: base-rate,
          features: validated-features
        }
      )
      (ok true)
    )
  )
)

;; Subscription management
(define-public (subscribe-to-tier (tier-name (string-ascii 10)))
  (let (
    (existing-subscription (map-get? subscriptions { user: tx-sender }))
    (tier-data (unwrap! (map-get? subscription-tiers { tier-name: tier-name }) ERR-INVALID-TIER))
  )
    (asserts! (validate-tier-name tier-name) ERR-INVALID-TIER)
    (asserts! (is-none existing-subscription) ERR-ALREADY-SUBSCRIBED)
    
    (let
      ((validated-tier-name tier-name))
      (map-set subscriptions 
        { user: tx-sender } 
        { 
          balance: u0,
          last-payment: stacks-block-height,
          rate: (get rate tier-data),
          active: false,
          tier: validated-tier-name
        }
      )
      (ok true)
    )
  )
)

(define-public (change-subscription-tier (new-tier (string-ascii 10)))
  (let (
    (user-subscription (unwrap! (map-get? subscriptions { user: tx-sender }) ERR-NOT-SUBSCRIBED))
    (new-tier-data (unwrap! (map-get? subscription-tiers { tier-name: new-tier }) ERR-INVALID-TIER))
  )
    (asserts! (validate-tier-name new-tier) ERR-INVALID-TIER)
    
    (let
      (
        (current-blocks-passed (- stacks-block-height (get last-payment user-subscription)))
        (consumed-tokens (* current-blocks-passed (get rate user-subscription)))
        (remaining-balance (if (>= consumed-tokens (get balance user-subscription))
                            u0
                            (- (get balance user-subscription) consumed-tokens)))
        (validated-tier new-tier)
      )
      (map-set subscriptions 
        { user: tx-sender } 
        (merge user-subscription { 
          balance: remaining-balance,
          last-payment: stacks-block-height,
          rate: (get rate new-tier-data),
          tier: validated-tier
        })
      )
      (ok validated-tier)
    )
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
    (current-blocks-passed (- stacks-block-height (get last-payment user-subscription)))
    (consumed-tokens (* current-blocks-passed (get rate user-subscription)))
    (remaining-balance (if (>= consumed-tokens (get balance user-subscription))
                        u0
                        (- (get balance user-subscription) consumed-tokens)))
  )
    (map-delete subscriptions { user: tx-sender })
    (ok remaining-balance)
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

;; Check if user has access to specific feature in their tier
(define-public (check-feature-access (user principal) (feature (string-ascii 20)))
  (let (
    (provider-data (unwrap! (map-get? service-providers { provider: tx-sender }) ERR-NOT-PROVIDER))
    (subscription-data (unwrap! (map-get? subscriptions { user: user }) ERR-NOT-SUBSCRIBED))
    (tier-name (get tier subscription-data))
    (tier-data (unwrap! (map-get? subscription-tiers { tier-name: tier-name }) ERR-INVALID-TIER))
    (tier-features (get features tier-data))
    (feature-index (index-of tier-features feature))
  )
    ;; Validate provider is authorized
    (asserts! (get authorized provider-data) ERR-NOT-AUTHORIZED)
    ;; Check if subscription is active and has sufficient balance
    (asserts! (get active subscription-data) ERR-NOT-SUBSCRIBED)
    
    ;; Check if the feature is available in user's tier using match
    (match feature-index
      index (ok true)
      (ok false)
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
        (tier-name (get tier sub))
        (tier-data (map-get? subscription-tiers { tier-name: tier-name }))
      )
        (if (and (get active sub) (> remaining-balance consumed-tokens))
          (ok {
            active: true,
            remaining-balance: (- remaining-balance consumed-tokens),
            rate: (get rate sub),
            tier: tier-name,
            tier-features: (match tier-data
              data (get features data)
              (list ))
          })
          (ok {
            active: false,
            remaining-balance: (get balance sub),
            rate: (get rate sub),
            tier: tier-name,
            tier-features: (match tier-data
              data (get features data)
              (list ))
          })
        )
      )
      (err ERR-NOT-SUBSCRIBED)
    )
  )
)

(define-read-only (get-tier-details (tier-name (string-ascii 10)))
  (map-get? subscription-tiers { tier-name: tier-name })
)

(define-read-only (is-service-provider (provider principal))
  (default-to false (get authorized (map-get? service-providers { provider: provider })))
)