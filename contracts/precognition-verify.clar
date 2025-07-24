;; Precognitive Ability Verification Contract
;; Tests and validates ability to perceive future events

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-PREDICTION-NOT-FOUND (err u302))
(define-constant ERR-ALREADY-VERIFIED (err u303))
(define-constant ERR-TOO-EARLY (err u304))
(define-constant ERR-TOO-LATE (err u305))

;; Data Variables
(define-data-var next-prediction-id uint u1)
(define-data-var verification-window uint u1000) ;; blocks
(define-data-var min-prediction-lead-time uint u100) ;; blocks

;; Data Maps
(define-map predictions
  { prediction-id: uint }
  {
    predictor: principal,
    event-description: (string-ascii 500),
    predicted-outcome: (string-ascii 200),
    confidence-level: uint,
    predicted-block: uint,
    verification-deadline: uint,
    created-at: uint,
    verified: bool,
    verification-result: (optional bool),
    verifier: (optional principal)
  }
)

(define-map prediction-categories
  { category: (string-ascii 50) }
  {
    total-predictions: uint,
    verified-predictions: uint,
    accurate-predictions: uint,
    category-difficulty: uint
  }
)

(define-map predictor-stats
  { predictor: principal }
  {
    total-predictions: uint,
    verified-predictions: uint,
    accurate-predictions: uint,
    accuracy-rate: uint,
    credibility-score: uint,
    specialization: (string-ascii 50),
    last-prediction: uint
  }
)

(define-map verification-challenges
  { challenge-id: uint }
  {
    challenger: principal,
    target-event: (string-ascii 300),
    prediction-deadline: uint,
    verification-deadline: uint,
    reward-amount: uint,
    participants: (list 20 principal),
    completed: bool
  }
)

(define-map challenge-submissions
  { challenge-id: uint, participant: principal }
  {
    prediction: (string-ascii 200),
    confidence: uint,
    submitted-at: uint,
    verified: bool,
    accuracy-score: uint
  }
)

;; Public Functions

;; Submit a precognitive prediction
(define-public (submit-prediction
  (event-description (string-ascii 500))
  (predicted-outcome (string-ascii 200))
  (confidence-level uint)
  (predicted-block uint)
  (category (string-ascii 50)))
  (let
    (
      (prediction-id (var-get next-prediction-id))
      (current-block block-height)
      (lead-time (- predicted-block current-block))
    )
    (asserts! (> (len event-description) u0) ERR-INVALID-INPUT)
    (asserts! (> (len predicted-outcome) u0) ERR-INVALID-INPUT)
    (asserts! (<= confidence-level u100) ERR-INVALID-INPUT)
    (asserts! (> predicted-block current-block) ERR-INVALID-INPUT)
    (asserts! (>= lead-time (var-get min-prediction-lead-time)) ERR-TOO-EARLY)

    (map-set predictions
      { prediction-id: prediction-id }
      {
        predictor: tx-sender,
        event-description: event-description,
        predicted-outcome: predicted-outcome,
        confidence-level: confidence-level,
        predicted-block: predicted-block,
        verification-deadline: (+ predicted-block (var-get verification-window)),
        created-at: current-block,
        verified: false,
        verification-result: none,
        verifier: none
      }
    )

    ;; Update category statistics
    (update-category-stats category)

    ;; Update predictor statistics
    (update-predictor-stats tx-sender)

    (var-set next-prediction-id (+ prediction-id u1))
    (ok prediction-id)
  )
)

;; Verify a prediction outcome
(define-public (verify-prediction (prediction-id uint) (outcome-accurate bool))
  (let
    (
      (prediction (unwrap! (map-get? predictions { prediction-id: prediction-id }) ERR-PREDICTION-NOT-FOUND))
      (current-block block-height)
    )
    (asserts! (>= current-block (get predicted-block prediction)) ERR-TOO-EARLY)
    (asserts! (<= current-block (get verification-deadline prediction)) ERR-TOO-LATE)
    (asserts! (not (get verified prediction)) ERR-ALREADY-VERIFIED)

    ;; Update prediction with verification
    (map-set predictions
      { prediction-id: prediction-id }
      (merge prediction {
        verified: true,
        verification-result: (some outcome-accurate),
        verifier: (some tx-sender)
      })
    )

    ;; Update predictor accuracy statistics
    (update-predictor-accuracy (get predictor prediction) outcome-accurate)

    (ok true)
  )
)

;; Create a prediction challenge
(define-public (create-challenge
  (target-event (string-ascii 300))
  (prediction-deadline uint)
  (verification-deadline uint)
  (reward-amount uint))
  (let
    (
      (challenge-id (var-get next-prediction-id)) ;; Reusing counter for simplicity
      (current-block block-height)
    )
    (asserts! (> (len target-event) u0) ERR-INVALID-INPUT)
    (asserts! (> prediction-deadline current-block) ERR-INVALID-INPUT)
    (asserts! (> verification-deadline prediction-deadline) ERR-INVALID-INPUT)

    (map-set verification-challenges
      { challenge-id: challenge-id }
      {
        challenger: tx-sender,
        target-event: target-event,
        prediction-deadline: prediction-deadline,
        verification-deadline: verification-deadline,
        reward-amount: reward-amount,
        participants: (list),
        completed: false
      }
    )

    (ok challenge-id)
  )
)

;; Submit prediction for challenge
(define-public (submit-challenge-prediction
  (challenge-id uint)
  (prediction (string-ascii 200))
  (confidence uint))
  (let
    (
      (challenge (unwrap! (map-get? verification-challenges { challenge-id: challenge-id }) ERR-PREDICTION-NOT-FOUND))
      (current-block block-height)
    )
    (asserts! (< current-block (get prediction-deadline challenge)) ERR-TOO-LATE)
    (asserts! (> (len prediction) u0) ERR-INVALID-INPUT)
    (asserts! (<= confidence u100) ERR-INVALID-INPUT)

    (map-set challenge-submissions
      { challenge-id: challenge-id, participant: tx-sender }
      {
        prediction: prediction,
        confidence: confidence,
        submitted-at: current-block,
        verified: false,
        accuracy-score: u0
      }
    )

    (ok true)
  )
)

;; Private Functions

;; Update category statistics
(define-private (update-category-stats (category (string-ascii 50)))
  (let
    (
      (current-stats (default-to
        { total-predictions: u0, verified-predictions: u0, accurate-predictions: u0, category-difficulty: u50 }
        (map-get? prediction-categories { category: category })
      ))
    )
    (map-set prediction-categories
      { category: category }
      (merge current-stats { total-predictions: (+ (get total-predictions current-stats) u1) })
    )
  )
)

;; Update predictor statistics
(define-private (update-predictor-stats (predictor principal))
  (let
    (
      (current-stats (default-to
        { total-predictions: u0, verified-predictions: u0, accurate-predictions: u0, accuracy-rate: u0, credibility-score: u50, specialization: "", last-prediction: u0 }
        (map-get? predictor-stats { predictor: predictor })
      ))
    )
    (map-set predictor-stats
      { predictor: predictor }
      (merge current-stats {
        total-predictions: (+ (get total-predictions current-stats) u1),
        last-prediction: block-height
      })
    )
  )
)

;; Update predictor accuracy after verification
(define-private (update-predictor-accuracy (predictor principal) (accurate bool))
  (let
    (
      (current-stats (unwrap-panic (map-get? predictor-stats { predictor: predictor })))
      (new-verified (+ (get verified-predictions current-stats) u1))
      (new-accurate (if accurate (+ (get accurate-predictions current-stats) u1) (get accurate-predictions current-stats)))
      (new-accuracy-rate (/ (* new-accurate u100) new-verified))
    )
    (map-set predictor-stats
      { predictor: predictor }
      (merge current-stats {
        verified-predictions: new-verified,
        accurate-predictions: new-accurate,
        accuracy-rate: new-accuracy-rate,
        credibility-score: (calculate-credibility-score new-accuracy-rate new-verified)
      })
    )
  )
)

;; Calculate credibility score based on accuracy and volume
(define-private (calculate-credibility-score (accuracy-rate uint) (total-verified uint))
  (let
    (
      (base-score accuracy-rate)
      (volume-bonus (if (> total-verified u10) u10 (/ total-verified u1)))
    )
    (if (> (+ base-score volume-bonus) u100) u100 (+ base-score volume-bonus))
  )
)

;; Read-only Functions

;; Get prediction details
(define-read-only (get-prediction (prediction-id uint))
  (map-get? predictions { prediction-id: prediction-id })
)

;; Get predictor statistics
(define-read-only (get-predictor-stats (predictor principal))
  (map-get? predictor-stats { predictor: predictor })
)

;; Get category statistics
(define-read-only (get-category-stats (category (string-ascii 50)))
  (map-get? prediction-categories { category: category })
)

;; Get challenge details
(define-read-only (get-challenge (challenge-id uint))
  (map-get? verification-challenges { challenge-id: challenge-id })
)

;; Get challenge submission
(define-read-only (get-challenge-submission (challenge-id uint) (participant principal))
  (map-get? challenge-submissions { challenge-id: challenge-id, participant: participant })
)

;; Calculate prediction accuracy for time period
(define-read-only (calculate-recent-accuracy (predictor principal) (blocks-back uint))
  (let
    (
      (stats (map-get? predictor-stats { predictor: predictor }))
      (cutoff-block (- block-height blocks-back))
    )
    (match stats
      predictor-data
        (if (and (> (get verified-predictions predictor-data) u0) (>= (get last-prediction predictor-data) cutoff-block))
          (get accuracy-rate predictor-data)
          u0
        )
      u0
    )
  )
)
