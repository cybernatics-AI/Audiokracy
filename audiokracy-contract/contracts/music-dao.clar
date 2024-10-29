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

(define-map reward-pools
    {cycle: uint}
    {total-amount: uint,
     distributed: bool})

;; Enhanced input validation functions
(define-private (validate-and-sanitize-token-id (token-id uint))
    (begin
        ;; Check basic bounds
        (asserts! (and 
            (>= token-id MIN-TOKEN-ID)
            (<= token-id MAX-TOKEN-ID)) 
            ERR-INVALID-TOKEN-ID)
        
        ;; Check against total tokens
        (asserts! (<= token-id (var-get total-tokens)) 
            ERR-INVALID-TOKEN-ID)
        
        ;; Verify token exists
        (match (map-get? tokens {id: token-id})
            token (ok token-id)
            ERR-NOT-FOUND)))

(define-private (verify-token-ownership (token-id uint) (owner principal))
    (match (map-get? tokens {id: token-id})
        token (ok (is-eq (get owner token) owner))
        ERR-NOT-FOUND))

;; Helper Functions
(define-private (check-not-paused)
    (if (var-get contract-paused)
        ERR-PAUSED
        (ok true)))

(define-private (check-not-blacklisted (address principal))
    (match (map-get? blacklist {address: address})
        blacklist-entry (if (>= block-height (get until blacklist-entry))
                           (ok true)
                           ERR-BLACKLISTED)
        (ok true)))

;; Safe transfer function with additional checks
(define-private (safe-transfer-shares (token-id uint) (from principal) (to principal) (amount uint))
    (let ((validated-token-id (try! (validate-and-sanitize-token-id token-id))))
        (let ((from-holdings (unwrap! (map-get? share-holdings 
                {token-id: validated-token-id, holder: from})
                ERR-NOT-FOUND))
              (to-holdings (default-to 
                {amount: u0, locked-until: u0}
                (map-get? share-holdings {token-id: validated-token-id, holder: to}))))
            
            ;; Additional safety checks
            (asserts! (>= (get amount from-holdings) amount) ERR-INSUFFICIENT-BALANCE)
            (asserts! (< (+ (get amount to-holdings) amount) (pow u2 u64)) ERR-INVALID-PARAMETER) ;; Prevent overflow
            
            (map-set share-holdings
                {token-id: validated-token-id, holder: from}
                {amount: (- (get amount from-holdings) amount),
                 locked-until: (get locked-until from-holdings)})
            
            (map-set share-holdings
                {token-id: validated-token-id, holder: to}
                {amount: (+ (get amount to-holdings) amount),
                 locked-until: (get locked-until to-holdings)})
            
            (ok true))))

;; Core Token Functions
(define-public (mint-token
    (metadata-url (string-utf8 256))
    (royalty-percentage uint)
    (total-shares uint))
    (begin
        (try! (check-not-paused))
        (try! (check-not-blacklisted tx-sender))
        (asserts! (>= (len metadata-url) u10) ERR-INVALID-PARAMETER)
        (asserts! (<= royalty-percentage MAX-ROYALTY-PERCENTAGE) ERR-INVALID-PARAMETER)
        (asserts! (and 
            (> total-shares u0)
            (< total-shares (pow u2 u64))) ERR-INVALID-PARAMETER)
        
        (let ((token-id (+ (var-get total-tokens) u1)))
            (try! (validate-and-sanitize-token-id token-id))
            (try! (ft-mint? music-shares total-shares tx-sender))
            (map-set tokens
                {id: token-id}
                {owner: tx-sender,
                 artist: tx-sender,
                 metadata-url: metadata-url,
                 royalty-percentage: royalty-percentage,
                 total-shares: total-shares,
                 locked: false,
                 created-at: block-height,
                 revenue-generated: u0,
                 verified: false})
            
            (map-set share-holdings
                {token-id: token-id, holder: tx-sender}
                {amount: total-shares,
                 locked-until: u0})
            
            (var-set total-tokens token-id)
            (ok token-id))))

;; Marketplace Functions
(define-public (list-shares
    (token-id uint)
    (shares-amount uint)
    (price uint))
    (let 
        ((validated-token-id (try! (validate-and-sanitize-token-id token-id))))
        (begin
            (try! (check-not-paused))
            (try! (check-not-blacklisted tx-sender))
            
            ;; Verify ownership
            (asserts! (unwrap! (verify-token-ownership validated-token-id tx-sender) ERR-NOT-FOUND)
                ERR-NOT-AUTHORIZED)
            
            ;; Price validation
            (asserts! (and 
                (>= price MIN-PRICE)
                (< price (pow u2 u64))) ;; Prevent overflow
                ERR-INVALID-PARAMETER)
            
            ;; Holdings validation
            (let ((holdings (unwrap! (map-get? share-holdings 
                    {token-id: validated-token-id, holder: tx-sender})
                    ERR-NOT-FOUND)))
                
                ;; Additional safety checks
                (asserts! (and
                    (>= (get amount holdings) shares-amount)
                    (> shares-amount u0)
                    (< shares-amount (pow u2 u64))) ;; Prevent overflow
                    ERR-INVALID-PARAMETER)
                
                (asserts! (>= block-height (get locked-until holdings)) 
                    ERR-STATE-INVALID)
                
                ;; Safe to proceed with listing
                (map-set listings
                    {token-id: validated-token-id}
                    {price: price,
                     seller: tx-sender,
                     expiry: (+ block-height u1440),
                     shares-amount: shares-amount,
                     auction-data: none})
                (ok true)))))

;; Secure purchase function
(define-public (purchase-shares (token-id uint))
    (let ((validated-token-id (try! (validate-and-sanitize-token-id token-id))))
        (begin
            (try! (check-not-paused))
            (try! (check-not-blacklisted tx-sender))
            
            (let ((listing (unwrap! (map-get? listings {token-id: validated-token-id}) 
                    ERR-NOT-FOUND))
                  (price (get price listing))
                  (seller (get seller listing))
                  (shares-amount (get shares-amount listing)))
                
                ;; Enhanced validations
                (asserts! (<= block-height (get expiry listing)) ERR-EXPIRED)
                (asserts! (not (is-eq tx-sender seller)) ERR-INVALID-PARAMETER)
                
                ;; Balance checks with overflow prevention
                (let ((balance (stx-get-balance tx-sender)))
                    (asserts! (and 
                        (>= balance price)
                        (>= price MIN-PRICE)
                        (< price (pow u2 u64))) ;; Prevent overflow
                        ERR-INSUFFICIENT-BALANCE))
                
                ;; Calculate fees with overflow prevention
                (let ((platform-fee (/ (* price PLATFORM-FEE-PERCENTAGE) u1000))
                      (seller-payment (- price platform-fee)))
                    
                    ;; Execute transfers
                    (try! (stx-transfer? platform-fee tx-sender (var-get platform-treasury)))
                    (try! (stx-transfer? seller-payment tx-sender seller))
                    
                    ;; Transfer shares using the safe transfer function
                    (match (map-get? share-holdings 
                            {token-id: validated-token-id, holder: seller})
                        seller-holdings 
                            (begin
                                (asserts! (>= (get amount seller-holdings) shares-amount) 
                                    ERR-INSUFFICIENT-BALANCE)
                                (try! (safe-transfer-shares validated-token-id seller tx-sender shares-amount))
                                (map-delete listings {token-id: validated-token-id})
                                (ok true))
                        ERR-NOT-FOUND))))))

;; Administrative Functions
(define-public (set-contract-paused (new-state bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-state (var-get contract-paused))) ERR-INVALID-PARAMETER)
        (var-set contract-paused new-state)
        (ok true)))

(define-public (set-platform-treasury (new-treasury principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-treasury (var-get platform-treasury))) ERR-INVALID-PARAMETER)
        (ok (var-set platform-treasury new-treasury))))

(define-public (trigger-emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set emergency-shutdown-active true)
        (var-set contract-paused true)
        (ok true)))