;; DeFi Shield: Decentralized Insurance Staking Protocol
;; This contract implements a decentralized insurance platform where users 
;; can stake tokens into a collective pool, earn proportional rewards,
;; and benefit from coverage against specified risks. The protocol uses
;; a democratic claim processing mechanism and features time-locked staking
;; to ensure pool stability.

;; Constants & Error Definitions

;; Administrative constants
(define-constant contract-admin tx-sender)
(define-constant minimum-stake-requirement u1000000) ;; 1 STX minimum stake
(define-constant staking-lockup-period u144) ;; ~24 hours at 10 min/block
(define-constant maximum-claim-amount u100000000) ;; 100 STX maximum claim amount
(define-constant maximum-reward-rate u1000) ;; 10% maximum reward rate (basis points)
(define-constant minimum-justification-length u5) ;; Minimum length for claim justification

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-STAKE-NOT-FOUND (err u102))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u103))
(define-constant ERR-CLAIM-REJECTED (err u104))
(define-constant ERR-MINIMUM-STAKE-REQUIREMENT (err u105))
(define-constant ERR-LOCKUP-PERIOD-ACTIVE (err u106))
(define-constant ERR-THRESHOLD-LIMIT-EXCEEDED (err u107))
(define-constant ERR-MAXIMUM-CLAIM-EXCEEDED (err u108))
(define-constant ERR-MAXIMUM-REWARD-RATE-EXCEEDED (err u109))
(define-constant ERR-INVALID-INPUT (err u110))
(define-constant ERR-JUSTIFICATION-TOO-SHORT (err u111))

;; Data Structures

;; Staker information
(define-map staker-records
  { participant-address: principal }
  { 
    staked-amount: uint, 
    deposit-block-height: uint, 
    reward-checkpoint-block: uint 
  }
)

;; Insurance claim records
(define-map claim-registry
  { claim-reference-id: uint }
  { 
    beneficiary-address: principal, 
    requested-payout: uint, 
    claim-justification: (string-utf8 256), 
    submission-block-height: uint,
    claim-status: (string-utf8 10) ;; "pending", "approved", "denied"
  }
)

;; Protocol State Variables

(define-data-var pool-total-balance uint u0)
(define-data-var total-insurance-payouts uint u0)
(define-data-var claim-sequence-counter uint u0)
(define-data-var annual-reward-rate uint u100) ;; 1% reward rate (basis points)
(define-data-var governance-approval-threshold uint u5100) ;; 51% approval requirement

;; Read-Only Functions

;; Get participant staking information
(define-read-only (get-participant-details (participant-address principal))
  (default-to
    { staked-amount: u0, deposit-block-height: u0, reward-checkpoint-block: u0 }
    (map-get? staker-records { participant-address: participant-address })
  )
)

;; Get insurance claim details
(define-read-only (get-claim-details (claim-reference-id uint))
  (map-get? claim-registry { claim-reference-id: claim-reference-id })
)

;; Get total assets in pool
(define-read-only (get-pool-liquidity)
  (var-get pool-total-balance)
)

;; Get historical insurance payouts
(define-read-only (get-historical-payouts)
  (var-get total-insurance-payouts)
)

;; Helper function to check string length
(define-read-only (get-string-length (some-string (string-utf8 256)))
  (len some-string)
)

;; Calculate pending reward distribution for a participant
(define-read-only (calculate-pending-rewards (participant-address principal))
  (let (
    (staker-info (get-participant-details participant-address))
    (staked-amount (get staked-amount staker-info))
    (last-checkpoint (get reward-checkpoint-block staker-info))
    (blocks-since-checkpoint (- block-height last-checkpoint))
  )
    (if (> staked-amount u0)
      ;; Calculate accrued rewards: amount * blocks * rate / 10000 (basis points)
      (/ (* (* staked-amount blocks-since-checkpoint) (var-get annual-reward-rate)) u10000)
      u0
    )
  )
)

;; Public Functions - Staking Operations

;; Deposit tokens into the insurance pool
(define-public (deposit-stake (deposit-amount uint))
  (let (
    (participant-record (get-participant-details tx-sender))
    (existing-stake (get staked-amount participant-record))
  )
    ;; Ensure minimum stake requirement is met
    (asserts! (>= deposit-amount minimum-stake-requirement) ERR-MINIMUM-STAKE-REQUIREMENT)
    
    ;; Transfer tokens from sender to contract
    (try! (stx-transfer? deposit-amount tx-sender (as-contract tx-sender)))
    
    ;; Process staking record update
    (if (> existing-stake u0)
      ;; Existing participant: claim pending rewards first
      (begin
        (try! (harvest-rewards))
        (map-set staker-records
          { participant-address: tx-sender }
          { 
            staked-amount: (+ existing-stake deposit-amount), 
            deposit-block-height: block-height,
            reward-checkpoint-block: block-height
          }
        )
      )
      ;; New participant registration
      (map-set staker-records
        { participant-address: tx-sender }
        { 
          staked-amount: deposit-amount, 
          deposit-block-height: block-height,
          reward-checkpoint-block: block-height
        }
      )
    )
    
    ;; Update pool total balance
    (var-set pool-total-balance (+ (var-get pool-total-balance) deposit-amount))
    
    (ok deposit-amount)
  )
)

;; Withdraw tokens from the insurance pool
(define-public (withdraw-stake (withdrawal-amount uint))
  (let (
    (participant-record (get-participant-details tx-sender))
    (staked-amount (get staked-amount participant-record))
    (deposit-timestamp (get deposit-block-height participant-record))
  )
    ;; Verify sufficient staked balance
    (asserts! (>= staked-amount withdrawal-amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Enforce lockup period compliance
    (asserts! (>= (- block-height deposit-timestamp) staking-lockup-period) 
              ERR-LOCKUP-PERIOD-ACTIVE)
    
    ;; Harvest any pending rewards first
    (try! (harvest-rewards))
    
    ;; Process withdrawal transfer
    (try! (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender)))
    
    ;; Update staking record
    (map-set staker-records
      { participant-address: tx-sender }
      { 
        staked-amount: (- staked-amount withdrawal-amount), 
        deposit-block-height: deposit-timestamp,
        reward-checkpoint-block: block-height
      }
    )
    
    ;; Update pool total balance
    (var-set pool-total-balance (- (var-get pool-total-balance) withdrawal-amount))
    
    (ok withdrawal-amount)
  )
)

;; Claim accrued staking rewards
(define-public (harvest-rewards)
  (let (
    (participant-record (get-participant-details tx-sender))
    (staked-amount (get staked-amount participant-record))
    (last-checkpoint (get reward-checkpoint-block participant-record))
    (accrued-rewards (calculate-pending-rewards tx-sender))
  )
    ;; Verify participant has active stake
    (asserts! (> staked-amount u0) ERR-STAKE-NOT-FOUND)
    
    ;; Process reward distribution if available
    (if (> accrued-rewards u0)
      (begin
        ;; Transfer rewards to participant
        (try! (as-contract (stx-transfer? accrued-rewards (as-contract tx-sender) tx-sender)))
        
        ;; Update reward checkpoint
        (map-set staker-records
          { participant-address: tx-sender }
          { 
            staked-amount: staked-amount, 
            deposit-block-height: (get deposit-block-height participant-record),
            reward-checkpoint-block: block-height
          }
        )
        
        (ok accrued-rewards)
      )
      (ok u0)
    )
  )
)

;; Public Functions - Insurance Claim Operations

;; Submit a new insurance claim
(define-public (file-insurance-claim (requested-amount uint) (claim-justification (string-utf8 256)))
  (let (
    (participant-record (get-participant-details tx-sender))
    (staked-amount (get staked-amount participant-record))
    (next-claim-id (var-get claim-sequence-counter))
    (justification-length (get-string-length claim-justification))
  )
    ;; Verify submitter is a staking participant
    (asserts! (> staked-amount u0) ERR-STAKE-NOT-FOUND)
    
    ;; Validate the requested payout amount
    (asserts! (and (> requested-amount u0) (<= requested-amount maximum-claim-amount)) 
              ERR-MAXIMUM-CLAIM-EXCEEDED)
    
    ;; Validate justification length to ensure it's not empty or too short
    (asserts! (>= justification-length minimum-justification-length) 
              ERR-JUSTIFICATION-TOO-SHORT)
    
    ;; Register new claim in registry with validated inputs
    (map-set claim-registry
      { claim-reference-id: next-claim-id }
      { 
        beneficiary-address: tx-sender, 
        requested-payout: requested-amount, 
        claim-justification: claim-justification, 
        submission-block-height: block-height,
        claim-status: u"pending"
      }
    )
    
    ;; Update sequence counter
    (var-set claim-sequence-counter (+ next-claim-id u1))
    
    (ok next-claim-id)
  )
)

;; Evaluate and process an insurance claim
(define-public (evaluate-claim (claim-reference-id uint) (approve-claim bool))
  (let (
    (claim-record (unwrap! (get-claim-details claim-reference-id) ERR-STAKE-NOT-FOUND))
    (beneficiary-address (get beneficiary-address claim-record))
    (requested-payout (get requested-payout claim-record))
    (current-status (get claim-status claim-record))
  )
    ;; Verify caller is contract administrator
    (asserts! (is-eq tx-sender contract-admin) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Ensure claim is in pending status
    (asserts! (is-eq current-status u"pending") ERR-CLAIM-ALREADY-PROCESSED)
    
    ;; For approved claims, verify sufficient pool liquidity
    (asserts! (or (not approve-claim) (>= (var-get pool-total-balance) requested-payout)) 
              ERR-INSUFFICIENT-BALANCE)
    
    (if approve-claim
      (begin
        ;; Process payout to beneficiary
        (try! (as-contract (stx-transfer? requested-payout (as-contract tx-sender) beneficiary-address)))
        
        ;; Update claim status to approved
        (map-set claim-registry
          { claim-reference-id: claim-reference-id }
          (merge claim-record { claim-status: u"approved" })
        )
        
        ;; Update protocol accounting
        (var-set total-insurance-payouts (+ (var-get total-insurance-payouts) requested-payout))
        (var-set pool-total-balance (- (var-get pool-total-balance) requested-payout))
        
        (ok true)
      )
      (begin
        ;; Update claim status to denied
        (map-set claim-registry
          { claim-reference-id: claim-reference-id }
          (merge claim-record { claim-status: u"denied" })
        )
        
        (ok false)
      )
    )
  )
)

;; Administrative Functions

;; Update protocol reward distribution rate
(define-public (configure-reward-rate (new-rate-basis-points uint))
  (begin
    ;; Verify caller is contract administrator
    (asserts! (is-eq tx-sender contract-admin) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate the new reward rate
    (asserts! (<= new-rate-basis-points maximum-reward-rate) ERR-MAXIMUM-REWARD-RATE-EXCEEDED)
    
    ;; Update the reward rate
    (var-set annual-reward-rate new-rate-basis-points)
    
    (ok new-rate-basis-points)
  )
)

;; Adjust governance threshold for claim approvals
(define-public (configure-governance-threshold (new-threshold-basis-points uint))
  (begin
    ;; Verify caller is contract administrator
    (asserts! (is-eq tx-sender contract-admin) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate the new threshold
    (asserts! (<= new-threshold-basis-points u10000) ERR-THRESHOLD-LIMIT-EXCEEDED)
    (asserts! (> new-threshold-basis-points u0) ERR-INVALID-INPUT)
    
    ;; Update the threshold
    (var-set governance-approval-threshold new-threshold-basis-points)
    
    (ok new-threshold-basis-points)
  )
)