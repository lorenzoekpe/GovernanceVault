;; GovernanceVault - Decentralized Treasury Management System

;; Constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_MOTION_EXISTS (err u101))
(define-constant ERR_MOTION_NOT_FOUND (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INVALID_CHOICE (err u105))
(define-constant ERR_SELF_REPRESENTATION (err u106))
(define-constant ERR_REPRESENTATION_CYCLE (err u107))
(define-constant ERR_INVALID_INPUT (err u108))
(define-constant ERR_NOT_ENOUGH_STAKE (err u109))
(define-constant ERR_INSUFFICIENT_SIGNATURES (err u110))

;; Data Variables
(define-data-var vault-guardian principal tx-sender)
(define-data-var epoch-counter uint u0)

;; Maps
(define-map Motions 
  { motion-id: uint } 
  { 
    title: (string-ascii 50), 
    choices: (list 10 (string-ascii 20)),
    deadline: uint,
    stake-total: uint
  }
)

(define-map Votes 
  { motion-id: uint, stakeholder: principal } 
  { choice: (string-ascii 20), stake: uint }
)

(define-map StakeholderPower 
  { stakeholder: principal } 
  { stake: uint }
)

(define-map Representatives
  { grantor: principal }
  { representative: principal }
)

;; Private Functions
(define-private (is-vault-guardian)
  (is-eq tx-sender (var-get vault-guardian))
)

(define-private (check-motion-exists (motion-id uint))
  (is-some (map-get? Motions { motion-id: motion-id }))
)

(define-private (check-voting-open (motion-id uint))
  (match (map-get? Motions { motion-id: motion-id })
    motion-data (< (var-get epoch-counter) (get deadline motion-data))
    false)
)

(define-private (get-stakeholder-power (stakeholder principal))
  (default-to u1 (get stake (map-get? StakeholderPower { stakeholder: stakeholder })))
)

(define-private (update-stake-total (motion-id uint) (stake uint))
  (match (map-get? Motions { motion-id: motion-id })
    motion-data (map-set Motions 
                { motion-id: motion-id }
                (merge motion-data { stake-total: (+ (get stake-total motion-data) stake) }))
    false)
)

(define-private (validate-string (input (string-ascii 50)))
  (and (>= (len input) u1) (<= (len input) u50))
)

(define-private (validate-choices (choices (list 10 (string-ascii 20))))
  (and 
    (>= (len choices) u2)
    (<= (len choices) u10)
    (fold and (map validate-string choices) true)
  )
)

(define-private (validate-stake-threshold (stakeholder principal))
  (> (get-stakeholder-power stakeholder) u0)
)

;; Public Functions
(define-public (propose-motion (title (string-ascii 50)) (choices (list 10 (string-ascii 20))) (duration uint))
  (begin
    (asserts! (is-vault-guardian) ERR_UNAUTHORIZED)
    (asserts! (validate-string title) ERR_INVALID_INPUT)
    (asserts! (validate-choices choices) ERR_INVALID_INPUT)
    (asserts! (> duration u0) ERR_INVALID_INPUT)
    (let 
      (
        (motion-id (+ u1 (default-to u0 (get stake-total (map-get? Motions { motion-id: u0 })))))
        (current-epoch (var-get epoch-counter))
      )
      (asserts! (not (check-motion-exists motion-id)) ERR_MOTION_EXISTS)
      (ok (map-set Motions 
            { motion-id: motion-id }
            { 
              title: title, 
              choices: choices,
              deadline: (+ current-epoch duration),
              stake-total: u0
            })))
  )
)

(define-public (cast-vote (motion-id uint) (choice (string-ascii 20)))
  (let 
    (
      (stakeholder-power (get-stakeholder-power tx-sender))
      (motion (unwrap! (map-get? Motions { motion-id: motion-id }) ERR_MOTION_NOT_FOUND))
    )
    (asserts! (check-voting-open motion-id) ERR_VOTING_ENDED)
    (asserts! (is-some (index-of (get choices motion) choice)) ERR_INVALID_CHOICE)
    (asserts! (is-none (map-get? Votes { motion-id: motion-id, stakeholder: tx-sender })) ERR_ALREADY_VOTED)
    (asserts! (validate-stake-threshold tx-sender) ERR_NOT_ENOUGH_STAKE)
    (map-set Votes 
      { motion-id: motion-id, stakeholder: tx-sender }
      { choice: choice, stake: stakeholder-power })
    (update-stake-total motion-id stakeholder-power)
    (ok true)
  )
)

(define-public (appoint-representative (representative principal))
  (begin
    (asserts! (not (is-eq tx-sender representative)) ERR_SELF_REPRESENTATION)
    (asserts! (is-none (map-get? Representatives { grantor: representative })) ERR_REPRESENTATION_CYCLE)
    (map-set Representatives { grantor: tx-sender } { representative: representative })
    (map-set StakeholderPower 
      { stakeholder: representative }
      { stake: (+ (get-stakeholder-power representative) (get-stakeholder-power tx-sender)) })
    (map-delete StakeholderPower { stakeholder: tx-sender })
    (ok true)
  )
)

(define-public (finalize-motion (motion-id uint))
  (begin
    (asserts! (is-vault-guardian) ERR_UNAUTHORIZED)
    (asserts! (check-motion-exists motion-id) ERR_MOTION_NOT_FOUND)
    (let ((motion (unwrap! (map-get? Motions { motion-id: motion-id }) ERR_MOTION_NOT_FOUND)))
      (ok (map-set Motions 
            { motion-id: motion-id }
            (merge motion { deadline: (var-get epoch-counter) })))
    )
  )
)

(define-public (advance-epoch)
  (begin
    (asserts! (is-vault-guardian) ERR_UNAUTHORIZED)
    (ok (var-set epoch-counter (+ (var-get epoch-counter) u1)))
  )
)

;; Read-Only Functions
(define-read-only (get-motion-stake-total (motion-id uint))
  (ok (get stake-total (unwrap! (map-get? Motions { motion-id: motion-id }) ERR_MOTION_NOT_FOUND)))
)

(define-read-only (get-stakeholder-power-level (stakeholder principal))
  (ok (get-stakeholder-power stakeholder))
)

(define-read-only (get-motion-status (motion-id uint))
  (let ((motion (unwrap! (map-get? Motions { motion-id: motion-id }) ERR_MOTION_NOT_FOUND)))
    (ok (< (var-get epoch-counter) (get deadline motion)))
  )
)

(define-read-only (get-current-epoch)
  (ok (var-get epoch-counter))
)