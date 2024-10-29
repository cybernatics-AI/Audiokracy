;; Music Rights and DAO Platform Contract
;; Core functionality for music rights management, marketplace, governance, and staking

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-PAUSED (err u1001))
(define-constant ERR-INVALID-PARAMETER (err u1002))
(define-constant ERR-NOT-FOUND (err u1003))
(define-constant ERR-PERMISSION-DENIED (err u1004))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1005))
(define-constant ERR-ALREADY-EXISTS (err u1006))
(define-constant ERR-STATE-INVALID (err u1007))
(define-constant ERR-CONTRACT-CALL-FAILED (err u1008))
(define-constant ERR-EXPIRED (err u1009))
(define-constant ERR-BLACKLISTED (err u1010))
(define-constant ERR-INVALID-TOKEN-ID (err u1011))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-ROYALTY-PERCENTAGE u250) ;; 25.0%
(define-constant PLATFORM-FEE-PERCENTAGE u20) ;; 2.0%
(define-constant MIN-PRICE u1000000) ;; in micro-STX
(define-constant MIN-STAKE-PERIOD u144) ;; ~24 hours in blocks
(define-constant PROPOSAL-DURATION u1008) ;; ~7 days in blocks
(define-constant MIN-STAKE-AMOUNT u100000000) ;; Minimum stake requirement
(define-constant REWARD-CYCLE-LENGTH u144) ;; ~24 hours in blocks
(define-constant MAX-BLACKLIST-DURATION u4320) ;; 30 days in blocks
(define-constant MAX-TOKEN-ID u1000000) ;; Maximum valid token ID
(define-constant MIN-TOKEN-ID u1) ;; Minimum valid token ID

;; Data Variables
(define-data-var total-tokens uint u0)
(define-data-var total-proposals uint u0)
(define-data-var contract-paused bool false)
(define-data-var platform-treasury principal CONTRACT-OWNER)
(define-data-var total-staked uint u0)
(define-data-var last-reward-cycle uint u0)
(define-data-var total-platform-revenue uint u0)
(define-data-var emergency-shutdown-active bool false)

;; Fungible Tokens
(define-fungible-token music-shares)
(define-fungible-token governance-token)
(define-fungible-token platform-token)

;; Data Maps
(define-map tokens
    {id: uint}
    {owner: principal,
     artist: principal,
     metadata-url: (string-utf8 256),
     royalty-percentage: uint,
     total-shares: uint,
     locked: bool,
     created-at: uint,
     revenue-generated: uint,
     verified: bool})

(define-map listings
    {token-id: uint}
    {price: uint,
     seller: principal,
     expiry: uint,
     shares-amount: uint,
     auction-data: (optional {
         start-price: uint,
         end-price: uint,
         highest-bidder: (optional principal),
         min-increment: uint
     })})

(define-map share-holdings
    {token-id: uint, holder: principal}
    {amount: uint,
     locked-until: uint})

(define-map staking-positions
    {staker: principal}
    {amount: uint,
     locked-until: uint,
     rewards-accumulated: uint,
     last-claim: uint})

(define-map governance-proposals
    {id: uint}
    {proposer: principal,
     title: (string-utf8 256),
     description: (string-utf8 1024),
     start-block: uint,
     end-block: uint,
     executed: bool,
     votes-for: uint,
     votes-against: uint,
     action: (string-utf8 256),
     minimum-votes: uint})

(define-map blacklist
    {address: principal}
    {until: uint,
     reason: (string-utf8 256)})
