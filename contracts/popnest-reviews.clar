;; popnest-reviews.clar
;; PopNest Community Reviews Platform

;; This contract manages the core functionality of PopNest, a decentralized platform
;; for pop culture reviews (movies, music, books, etc.). It handles review creation,
;; storage, voting, reputation tracking, and content moderation. The platform is 
;; designed to be community-owned with quality content surfaced through a reputation-weighted
;; voting system.

;; =======================================
;; Constants and Error Codes
;; =======================================

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-REVIEW (err u101))
(define-constant ERR-REVIEW-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-CANNOT-VOTE-OWN-REVIEW (err u104))
(define-constant ERR-INVALID-CATEGORY (err u105))
(define-constant ERR-INVALID-FLAG (err u106))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u107))
(define-constant ERR-ALREADY-FLAGGED (err u108))

;; Category codes
(define-constant CATEGORY-MOVIE u1)
(define-constant CATEGORY-MUSIC u2)
(define-constant CATEGORY-BOOK u3)
(define-constant CATEGORY-TV u4)
(define-constant CATEGORY-GAME u5)
(define-constant CATEGORY-OTHER u6)

;; Reputation thresholds
(define-constant MIN-REPUTATION-TO-FLAG u10)
(define-constant BASE-REPUTATION u1)
(define-constant UPVOTE-REPUTATION-REWARD u1)
(define-constant DOWNVOTE-REPUTATION-PENALTY u1)

;; =======================================
;; Data Maps and Variables
;; =======================================

;; Review data structure
(define-map reviews
  { review-id: uint }
  {
    author: principal,
    title: (string-utf8 100),
    content: (string-utf8 5000),
    category: uint,
    item-name: (string-utf8 100),
    rating: uint,
    created-at: uint,
    upvotes: uint,
    downvotes: uint,
    is-flagged: bool
  }
)

;; Keep track of the next available review ID
(define-data-var next-review-id uint u1)

;; Track user reputation
(define-map user-reputation
  { user: principal }
  { score: uint }
)

;; Track user votes to prevent double voting
(define-map user-votes
  { user: principal, review-id: uint }
  { vote-type: bool } ;; true for upvote, false for downvote
)

;; Track flags on reviews
(define-map review-flags
  { review-id: uint, flagger: principal }
  { reason: (string-utf8 200) }
)

;; Track reviews by category for easy discovery
(define-map category-reviews
  { category: uint }
  { review-ids: (list 100 uint) }
)

;; Track reviews by author
(define-map author-reviews
  { author: principal }
  { review-ids: (list 100 uint) }
)

;; =======================================
;; Private Functions
;; =======================================

;; Get user's reputation (returns BASE_REPUTATION for new users)
(define-private (get-user-reputation (user principal))
  (default-to { score: BASE-REPUTATION } (map-get? user-reputation { user: user }))
)

;; Update user's reputation
(define-private (update-user-reputation (user principal) (new-score uint))
  (map-set user-reputation { user: user } { score: new-score })
)

;; Add a review to the category index
(define-private (add-to-category-index (category uint) (review-id uint))
  (let ((current-list (default-to { review-ids: (list) } (map-get? category-reviews { category: category }))))
    (map-set category-reviews 
      { category: category } 
      { review-ids: (unwrap-panic (as-max-len? (append (get review-ids current-list) review-id) u100)) }
    )
  )
)

;; Add a review to the author index
(define-private (add-to-author-index (author principal) (review-id uint))
  (let ((current-list (default-to { review-ids: (list) } (map-get? author-reviews { author: author }))))
    (map-set author-reviews 
      { author: author } 
      { review-ids: (unwrap-panic (as-max-len? (append (get review-ids current-list) review-id) u100)) }
    )
  )
)

;; Check if a category is valid
(define-private (is-valid-category (category uint))
  (or
    (is-eq category CATEGORY-MOVIE)
    (is-eq category CATEGORY-MUSIC)
    (is-eq category CATEGORY-BOOK)
    (is-eq category CATEGORY-TV)
    (is-eq category CATEGORY-GAME)
    (is-eq category CATEGORY-OTHER)
  )
)

;; Check if a rating is valid (1-10)
(define-private (is-valid-rating (rating uint))
  (and (>= rating u1) (<= rating u10))
)

;; =======================================
;; Read-Only Functions
;; =======================================

;; Get review by ID
(define-read-only (get-review (review-id uint))
  (map-get? reviews { review-id: review-id })
)

;; Get user reputation
(define-read-only (get-reputation (user principal))
  (get score (get-user-reputation user))
)

;; Get reviews by category
(define-read-only (get-reviews-by-category (category uint))
  (default-to { review-ids: (list) } (map-get? category-reviews { category: category }))
)

;; Get reviews by author
(define-read-only (get-reviews-by-author (author principal))
  (default-to { review-ids: (list) } (map-get? author-reviews { author: author }))
)

;; Check if user has voted on a specific review
(define-read-only (has-voted (user principal) (review-id uint))
  (is-some (map-get? user-votes { user: user, review-id: review-id }))
)

;; =======================================
;; Public Functions
;; =======================================

;; Create a new review
(define-public (create-review 
  (title (string-utf8 100)) 
  (content (string-utf8 5000)) 
  (category uint) 
  (item-name (string-utf8 100)) 
  (rating uint))
  
  (let ((review-id (var-get next-review-id)))
    ;; Check if inputs are valid
    (asserts! (and (> (len title) u0) (> (len content) u0) (> (len item-name) u0)) ERR-INVALID-REVIEW)
    (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
    (asserts! (is-valid-rating rating) ERR-INVALID-REVIEW)
    
    ;; Store the review
    (map-set reviews 
      { review-id: review-id }
      {
        author: tx-sender,
        title: title,
        content: content,
        category: category,
        item-name: item-name,
        rating: rating,
        created-at: block-height,
        upvotes: u0,
        downvotes: u0,
        is-flagged: false
      }
    )
    
    ;; Update indexes
    (add-to-category-index category review-id)
    (add-to-author-index tx-sender review-id)
    
    ;; Increment the review ID counter
    (var-set next-review-id (+ review-id u1))
    
    (ok review-id)
  )
)

;; Upvote a review
(define-public (upvote-review (review-id uint))
  (let (
    (review (unwrap! (get-review review-id) ERR-REVIEW-NOT-FOUND))
    (voter-reputation (get-reputation tx-sender))
  )
    ;; Check if the user can vote on this review
    (asserts! (not (is-eq (get author review) tx-sender)) ERR-CANNOT-VOTE-OWN-REVIEW)
    (asserts! (not (has-voted tx-sender review-id)) ERR-ALREADY-VOTED)
    
    ;; Update the review's vote count
    (map-set reviews
      { review-id: review-id }
      (merge review { upvotes: (+ (get upvotes review) u1) })
    )
    
    ;; Record the user's vote
    (map-set user-votes
      { user: tx-sender, review-id: review-id }
      { vote-type: true }
    )
    
    ;; Reward the review author with reputation
    (let ((author (get author review))
          (author-reputation (get-reputation author)))
      (update-user-reputation 
        author 
        (+ (get score author-reputation) UPVOTE-REPUTATION-REWARD)
      )
    )
    
    (ok true)
  )
)

;; Downvote a review
(define-public (downvote-review (review-id uint))
  (let (
    (review (unwrap! (get-review review-id) ERR-REVIEW-NOT-FOUND))
    (voter-reputation (get-reputation tx-sender))
  )
    ;; Check if the user can vote on this review
    (asserts! (not (is-eq (get author review) tx-sender)) ERR-CANNOT-VOTE-OWN-REVIEW)
    (asserts! (not (has-voted tx-sender review-id)) ERR-ALREADY-VOTED)
    
    ;; Update the review's vote count
    (map-set reviews
      { review-id: review-id }
      (merge review { downvotes: (+ (get downvotes review) u1) })
    )
    
    ;; Record the user's vote
    (map-set user-votes
      { user: tx-sender, review-id: review-id }
      { vote-type: false }
    )
    
    ;; Penalize the review author with reputation loss, but ensure it doesn't go below BASE_REPUTATION
    (let* ((author (get author review))
          (author-reputation (get-reputation author))
          (new-score (if (> (get score author-reputation) (+ BASE-REPUTATION DOWNVOTE-REPUTATION-PENALTY))
                       (- (get score author-reputation) DOWNVOTE-REPUTATION-PENALTY)
                       BASE-REPUTATION)))
      (update-user-reputation author new-score)
    )
    
    (ok true)
  )
)

;; Flag a review for inappropriate content (requires minimum reputation)
(define-public (flag-review (review-id uint) (reason (string-utf8 200)))
  (let (
    (review (unwrap! (get-review review-id) ERR-REVIEW-NOT-FOUND))
    (flagger-reputation (get-reputation tx-sender))
  )
    ;; Check if the flagger has sufficient reputation
    (asserts! (>= (get score flagger-reputation) MIN-REPUTATION-TO-FLAG) ERR-INSUFFICIENT-REPUTATION)
    
    ;; Check if the user has already flagged this review
    (asserts! (is-none (map-get? review-flags { review-id: review-id, flagger: tx-sender })) ERR-ALREADY-FLAGGED)
    
    ;; Must provide a reason
    (asserts! (> (len reason) u0) ERR-INVALID-FLAG)
    
    ;; Record the flag
    (map-set review-flags
      { review-id: review-id, flagger: tx-sender }
      { reason: reason }
    )
    
    ;; Mark the review as flagged
    (map-set reviews
      { review-id: review-id }
      (merge review { is-flagged: true })
    )
    
    (ok true)
  )
)

;; Initialize a new user's reputation (can only be called once per user)
(define-public (init-user-reputation)
  (let ((existing-reputation (map-get? user-reputation { user: tx-sender })))
    (if (is-some existing-reputation)
        (ok true) ;; User already has reputation, do nothing
        (begin
          (map-set user-reputation { user: tx-sender } { score: BASE-REPUTATION })
          (ok true)
        )
    )
  )
)