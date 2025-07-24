;; Psychic Ability Training Coordination Contract
;; Systematically develops natural psychic capabilities

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-INPUT (err u201))
(define-constant ERR-SESSION-NOT-FOUND (err u202))
(define-constant ERR-ALREADY-ENROLLED (err u203))
(define-constant ERR-NOT-ENROLLED (err u204))

;; Data Variables
(define-data-var next-session-id uint u1)
(define-data-var next-program-id uint u1)
(define-data-var total-trainers uint u0)

;; Data Maps
(define-map training-programs
  { program-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    trainer: principal,
    ability-type: (string-ascii 50),
    duration-blocks: uint,
    max-participants: uint,
    current-participants: uint,
    created-at: uint,
    is-active: bool
  }
)

(define-map training-sessions
  { session-id: uint }
  {
    program-id: uint,
    session-name: (string-ascii 100),
    scheduled-block: uint,
    duration: uint,
    participants: (list 50 principal),
    exercises: (list 10 (string-ascii 200)),
    completed: bool,
    results-recorded: bool
  }
)

(define-map participant-enrollment
  { program-id: uint, participant: principal }
  {
    enrolled-at: uint,
    progress-level: uint,
    sessions-attended: uint,
    total-sessions: uint,
    skill-rating: uint,
    last-session: uint
  }
)

(define-map session-results
  { session-id: uint, participant: principal }
  {
    attendance: bool,
    performance-score: uint,
    exercises-completed: uint,
    feedback: (string-ascii 300),
    improvement-noted: bool
  }
)

(define-map trainer-credentials
  { trainer: principal }
  {
    specializations: (list 5 (string-ascii 50)),
    experience-level: uint,
    programs-created: uint,
    total-students: uint,
    average-rating: uint,
    certified: bool
  }
)

;; Public Functions

;; Create a new training program
(define-public (create-training-program
  (name (string-ascii 100))
  (description (string-ascii 500))
  (ability-type (string-ascii 50))
  (duration-blocks uint)
  (max-participants uint))
  (let
    (
      (program-id (var-get next-program-id))
      (current-block block-height)
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> duration-blocks u0) ERR-INVALID-INPUT)
    (asserts! (> max-participants u0) ERR-INVALID-INPUT)
    (asserts! (< max-participants u51) ERR-INVALID-INPUT)

    (map-set training-programs
      { program-id: program-id }
      {
        name: name,
        description: description,
        trainer: tx-sender,
        ability-type: ability-type,
        duration-blocks: duration-blocks,
        max-participants: max-participants,
        current-participants: u0,
        created-at: current-block,
        is-active: true
      }
    )

    ;; Update trainer credentials
    (update-trainer-stats tx-sender)

    (var-set next-program-id (+ program-id u1))
    (ok program-id)
  )
)

;; Enroll in a training program
(define-public (enroll-in-program (program-id uint))
  (let
    (
      (program (unwrap! (map-get? training-programs { program-id: program-id }) ERR-SESSION-NOT-FOUND))
      (current-block block-height)
    )
    (asserts! (get is-active program) ERR-INVALID-INPUT)
    (asserts! (< (get current-participants program) (get max-participants program)) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? participant-enrollment { program-id: program-id, participant: tx-sender })) ERR-ALREADY-ENROLLED)

    ;; Record enrollment
    (map-set participant-enrollment
      { program-id: program-id, participant: tx-sender }
      {
        enrolled-at: current-block,
        progress-level: u1,
        sessions-attended: u0,
        total-sessions: u0,
        skill-rating: u0,
        last-session: u0
      }
    )

    ;; Update program participant count
    (map-set training-programs
      { program-id: program-id }
      (merge program { current-participants: (+ (get current-participants program) u1) })
    )

    (ok true)
  )
)

;; Schedule a training session
(define-public (schedule-session
  (program-id uint)
  (session-name (string-ascii 100))
  (scheduled-block uint)
  (duration uint)
  (exercises (list 10 (string-ascii 200))))
  (let
    (
      (program (unwrap! (map-get? training-programs { program-id: program-id }) ERR-SESSION-NOT-FOUND))
      (session-id (var-get next-session-id))
    )
    (asserts! (is-eq tx-sender (get trainer program)) ERR-NOT-AUTHORIZED)
    (asserts! (> scheduled-block block-height) ERR-INVALID-INPUT)
    (asserts! (> duration u0) ERR-INVALID-INPUT)

    (map-set training-sessions
      { session-id: session-id }
      {
        program-id: program-id,
        session-name: session-name,
        scheduled-block: scheduled-block,
        duration: duration,
        participants: (list),
        exercises: exercises,
        completed: false,
        results-recorded: false
      }
    )

    (var-set next-session-id (+ session-id u1))
    (ok session-id)
  )
)

;; Record session attendance and results
(define-public (record-session-result
  (session-id uint)
  (participant principal)
  (performance-score uint)
  (exercises-completed uint)
  (feedback (string-ascii 300)))
  (let
    (
      (session (unwrap! (map-get? training-sessions { session-id: session-id }) ERR-SESSION-NOT-FOUND))
      (program (unwrap! (map-get? training-programs { program-id: (get program-id session) }) ERR-SESSION-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get trainer program)) ERR-NOT-AUTHORIZED)
    (asserts! (<= performance-score u100) ERR-INVALID-INPUT)

    (map-set session-results
      { session-id: session-id, participant: participant }
      {
        attendance: true,
        performance-score: performance-score,
        exercises-completed: exercises-completed,
        feedback: feedback,
        improvement-noted: (> performance-score u70)
      }
    )

    ;; Update participant progress
    (update-participant-progress (get program-id session) participant performance-score)

    (ok true)
  )
)

;; Private Functions

;; Update trainer statistics
(define-private (update-trainer-stats (trainer principal))
  (let
    (
      (current-stats (default-to
        { specializations: (list), experience-level: u1, programs-created: u0, total-students: u0, average-rating: u0, certified: false }
        (map-get? trainer-credentials { trainer: trainer })
      ))
    )
    (map-set trainer-credentials
      { trainer: trainer }
      (merge current-stats { programs-created: (+ (get programs-created current-stats) u1) })
    )
  )
)

;; Update participant progress after session
(define-private (update-participant-progress (program-id uint) (participant principal) (score uint))
  (let
    (
      (enrollment (map-get? participant-enrollment { program-id: program-id, participant: participant }))
    )
    (match enrollment
      participant-data
        (map-set participant-enrollment
          { program-id: program-id, participant: participant }
          (merge participant-data {
            sessions-attended: (+ (get sessions-attended participant-data) u1),
            skill-rating: (/ (+ (get skill-rating participant-data) score) u2),
            last-session: block-height
          })
        )
      false
    )
  )
)

;; Read-only Functions

;; Get training program details
(define-read-only (get-training-program (program-id uint))
  (map-get? training-programs { program-id: program-id })
)

;; Get training session details
(define-read-only (get-training-session (session-id uint))
  (map-get? training-sessions { session-id: session-id })
)

;; Get participant enrollment status
(define-read-only (get-participant-enrollment (program-id uint) (participant principal))
  (map-get? participant-enrollment { program-id: program-id, participant: participant })
)

;; Get session results for participant
(define-read-only (get-session-results (session-id uint) (participant principal))
  (map-get? session-results { session-id: session-id, participant: participant })
)

;; Get trainer credentials
(define-read-only (get-trainer-credentials (trainer principal))
  (map-get? trainer-credentials { trainer: trainer })
)

;; Calculate participant progress percentage
(define-read-only (calculate-progress-percentage (program-id uint) (participant principal))
  (let
    (
      (enrollment (map-get? participant-enrollment { program-id: program-id, participant: participant }))
    )
    (match enrollment
      participant-data
        (if (> (get total-sessions participant-data) u0)
          (/ (* (get sessions-attended participant-data) u100) (get total-sessions participant-data))
          u0
        )
      u0
    )
  )
)
