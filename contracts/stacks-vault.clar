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