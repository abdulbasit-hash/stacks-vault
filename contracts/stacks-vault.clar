;; StacksVault - Decentralized Content Registry
;;
;; A sophisticated smart contract for registering, managing, and verifying
;; digital content ownership on the Stacks blockchain. This contract enables
;; creators to establish immutable proof of ownership for their digital works
;; while leveraging Bitcoin's security through the Stacks protocol.
;;
;; Key Features:
;; - Cryptographic content fingerprinting using SHA-256 hashes
;; - Decentralized ownership verification without intermediaries
;; - Seamless content transfers with automatic bookkeeping
;; - Gas-efficient storage architecture optimized for Stacks
;; - Built-in content lifecycle management

;; CORE CONSTANTS & ERROR HANDLING

;; Contract deployment authority - immutable after deployment
(define-constant VAULT-ADMIN tx-sender)

;; Comprehensive error code system for robust error handling
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-CONTENT-NOT-REGISTERED (err u101))
(define-constant ERR-DUPLICATE-CONTENT-HASH (err u102))
(define-constant ERR-MALFORMED-INPUT (err u103))
(define-constant ERR-OPERATION-FAILED (err u104))
(define-constant ERR-INVALID-VAULT-ID (err u105))

;; Input validation constants
(define-constant MAX-VAULT-ID u1000000) ;; Reasonable upper limit for vault IDs
(define-constant MIN-TITLE-LENGTH u1)
(define-constant MAX-TITLE-LENGTH u256)
(define-constant MAX-DESCRIPTION-LENGTH u1024)
(define-constant MIN-CATEGORY-LENGTH u1)
(define-constant MAX-CATEGORY-LENGTH u64)

;; STATE VARIABLES

;; Auto-incrementing content identifier for efficient indexing
(define-data-var content-sequence-id uint u1)

;; DATA STRUCTURES

;; Primary content registry - stores comprehensive metadata for each registered item
;; Optimized for both storage efficiency and query performance on Stacks
(define-map digital-content-vault
  { vault-id: uint }
  {
    content-owner: principal,
    asset-title: (string-ascii 256),
    asset-description: (string-ascii 1024),
    cryptographic-fingerprint: (buff 32),
    media-category: (string-ascii 64),
    registration-block: uint,
    last-modified-block: uint,
    vault-status: bool,
  }
)

;; Hash-to-ID mapping for O(1) content lookup by cryptographic fingerprint
;; Essential for preventing duplicate registrations and enabling fast verification
(define-map fingerprint-index
  { cryptographic-fingerprint: (buff 32) }
  { vault-id: uint }
)

;; Owner portfolio tracker - maintains real-time count of registered content per user
;; Enables efficient portfolio queries and analytics
(define-map creator-portfolio
  { content-owner: principal }
  { registered-count: uint }
)

;; PRIVATE HELPER FUNCTIONS

;; Validate string inputs to prevent malformed data storage
(define-private (validate-string-input
    (input (string-ascii 1024))
    (min-len uint)
    (max-len uint)
  )
  (and
    (>= (len input) min-len)
    (<= (len input) max-len)
  )
)

;; Validate vault ID to ensure it's within reasonable bounds
(define-private (validate-vault-id (vault-id uint))
  (and
    (> vault-id u0)
    (<= vault-id MAX-VAULT-ID)
  )
)

;; Sanitize and validate media category input
(define-private (validate-media-category (category (string-ascii 64)))
  (and
    (>= (len category) MIN-CATEGORY-LENGTH)
    (<= (len category) MAX-CATEGORY-LENGTH)
  )
)

;; PUBLIC INTERFACE FUNCTIONS

;; Register new digital content with cryptographic proof of ownership
;; This function creates an immutable record on the Stacks blockchain,
;; providing tamper-proof evidence of content creation and ownership
(define-public (register-digital-asset
    (asset-title (string-ascii 256))
    (asset-description (string-ascii 1024))
    (cryptographic-fingerprint (buff 32))
    (media-category (string-ascii 64))
  )
  (let (
      (new-vault-id (var-get content-sequence-id))
      (current-block-height stacks-block-height)
    )
    ;; Comprehensive input validation - ensure data integrity before blockchain storage
    (asserts!
      (validate-string-input asset-title MIN-TITLE-LENGTH MAX-TITLE-LENGTH)
      ERR-MALFORMED-INPUT
    )
    (asserts! (validate-string-input asset-description u0 MAX-DESCRIPTION-LENGTH)
      ERR-MALFORMED-INPUT
    )
    (asserts! (validate-media-category media-category) ERR-MALFORMED-INPUT)
    (asserts! (is-eq (len cryptographic-fingerprint) u32) ERR-MALFORMED-INPUT)
    (asserts!
      (is-none (map-get? fingerprint-index { cryptographic-fingerprint: cryptographic-fingerprint }))
      ERR-DUPLICATE-CONTENT-HASH
    )

    ;; Create immutable content record in the vault
    (map-set digital-content-vault { vault-id: new-vault-id } {
      content-owner: tx-sender,
      asset-title: asset-title,
      asset-description: asset-description,
      cryptographic-fingerprint: cryptographic-fingerprint,
      media-category: media-category,
      registration-block: current-block-height,
      last-modified-block: current-block-height,
      vault-status: true,
    })

    ;; Index the cryptographic fingerprint for fast duplicate detection
    (map-set fingerprint-index { cryptographic-fingerprint: cryptographic-fingerprint } { vault-id: new-vault-id })

    ;; Update the creator's portfolio statistics
    (let ((existing-count (default-to u0
        (get registered-count
          (map-get? creator-portfolio { content-owner: tx-sender })
        ))))
      (map-set creator-portfolio { content-owner: tx-sender } { registered-count: (+ existing-count u1) })
    )

    ;; Advance the sequence counter for next registration
    (var-set content-sequence-id (+ new-vault-id u1))

    ;; Return the newly created vault ID
    (ok new-vault-id)
  )
)

;; Transfer content ownership between Stacks addresses
;; Enables decentralized content trading and inheritance scenarios
;; while maintaining complete ownership history on-chain
(define-public (transfer-content-ownership
    (vault-id uint)
    (recipient principal)
  )
  (let (
      (vault-record (unwrap! (map-get? digital-content-vault { vault-id: vault-id })
        ERR-CONTENT-NOT-REGISTERED
      ))
      (current-owner (get content-owner vault-record))
    )
    ;; Input validation for vault ID
    (asserts! (validate-vault-id vault-id) ERR-INVALID-VAULT-ID)

    ;; Authorization check - only current owner can initiate transfers
    (asserts! (is-eq tx-sender current-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (is-eq current-owner recipient)) ERR-MALFORMED-INPUT)

    ;; Execute ownership transfer with timestamp update
    (map-set digital-content-vault { vault-id: vault-id }
      (merge vault-record {
        content-owner: recipient,
        last-modified-block: stacks-block-height,
      })
    )

    ;; Update portfolio statistics for both parties
    (let (
        (sender-count (default-to u0
          (get registered-count
            (map-get? creator-portfolio { content-owner: current-owner })
          )))
        (recipient-count (default-to u0
          (get registered-count
            (map-get? creator-portfolio { content-owner: recipient })
          )))
      )
      ;; Decrement sender's portfolio count
      (map-set creator-portfolio { content-owner: current-owner } { registered-count: (- sender-count u1) })
      ;; Increment recipient's portfolio count
      (map-set creator-portfolio { content-owner: recipient } { registered-count: (+ recipient-count u1) })
    )

    (ok true)
  )
)

;; Update content metadata while preserving ownership and cryptographic proof
;; Allows creators to refine descriptions and titles without affecting
;; the core cryptographic fingerprint that proves content authenticity
(define-public (update-asset-metadata
    (vault-id uint)
    (asset-title (string-ascii 256))
    (asset-description (string-ascii 1024))
  )
  (let ((vault-record (unwrap! (map-get? digital-content-vault { vault-id: vault-id })
      ERR-CONTENT-NOT-REGISTERED
    )))
    ;; Input validation
    (asserts! (validate-vault-id vault-id) ERR-INVALID-VAULT-ID)
    (asserts!
      (validate-string-input asset-title MIN-TITLE-LENGTH MAX-TITLE-LENGTH)
      ERR-MALFORMED-INPUT
    )
    (asserts! (validate-string-input asset-description u0 MAX-DESCRIPTION-LENGTH)
      ERR-MALFORMED-INPUT
    )

    ;; Authorization check - only content owner can update metadata
    (asserts! (is-eq tx-sender (get content-owner vault-record))
      ERR-UNAUTHORIZED-ACCESS
    )

    ;; Update metadata while preserving cryptographic integrity
    (map-set digital-content-vault { vault-id: vault-id }
      (merge vault-record {
        asset-title: asset-title,
        asset-description: asset-description,
        last-modified-block: stacks-block-height,
      })
    )

    (ok true)
  )
)

;; Archive content by setting inactive status
;; Provides a way to logically remove content from active circulation
;; without destroying the immutable ownership record on Stacks
(define-public (archive-digital-content (vault-id uint))
  (let ((vault-record (unwrap! (map-get? digital-content-vault { vault-id: vault-id })
      ERR-CONTENT-NOT-REGISTERED
    )))
    ;; Input validation for vault ID
    (asserts! (validate-vault-id vault-id) ERR-INVALID-VAULT-ID)

    ;; Authorization check - only content owner can archive
    (asserts! (is-eq tx-sender (get content-owner vault-record))
      ERR-UNAUTHORIZED-ACCESS
    )

    ;; Set archive status while maintaining all other data
    (map-set digital-content-vault { vault-id: vault-id }
      (merge vault-record {
        vault-status: false,
        last-modified-block: stacks-block-height,
      })
    )

    (ok true)
  )
)

;; READ-ONLY QUERY FUNCTIONS

;; Retrieve complete content record by vault ID
;; Returns all metadata and ownership information for verification
(define-read-only (get-vault-record (vault-id uint))
  (if (validate-vault-id vault-id)
    (map-get? digital-content-vault { vault-id: vault-id })
    none
  )
)