(export #t)

(import
  :clan/debug
  :gerbil/gambit/bits :gerbil/gambit/bytes :gerbil/gambit/threads :gerbil/gambit/ports :std/net/bio
  :gerbil/gambit
  :std/assert :std/crypto :std/format :std/iter
  :std/misc/threads
  :std/misc/hash :std/misc/list :std/misc/number :std/misc/uuid :std/misc/channel :std/text/utf8 :std/text/base64
  :std/os/pid :std/os/signal
  :std/pregexp
  :std/sort
  :std/srfi/1 :std/srfi/13
  :std/sugar
  :std/text/base64 :std/text/json :std/text/csv :std/db/sqlite :std/db/dbi :std/iter
  (for-syntax :std/stxutil)
  :gerbil/gambit/exceptions
  :clan/base :clan/exception :clan/io :clan/json :clan/net/tcp :clan/number :clan/pure/dict/assq
  :clan/path :clan/path-config :clan/ports :clan/syntax :clan/timestamp
  :clan/poo/object :clan/poo/brace :clan/poo/io :clan/poo/debug :clan/debug :clan/crypto/random
  :clan/persist/content-addressing :clan/shell
  :mukn/ethereum/hex :mukn/ethereum/ethereum :mukn/ethereum/network-config :mukn/ethereum/json-rpc
  :mukn/ethereum/transaction :mukn/ethereum/tx-tracker :mukn/ethereum/watch :mukn/ethereum/assets
  :mukn/ethereum/evm-runtime :mukn/ethereum/contract-config :mukn/ethereum/assembly :mukn/ethereum/types
  :mukn/ethereum/nonce-tracker
  (only-in :mukn/glow/compiler/common hash-kref)
  :vyzo/libp2p
  (only-in ../compiler/alpha-convert/env symbol-refer)
  ./program ./block-ctx ./consensus-code-generator ./terminal-codes
  ./pb/private-key
  ../compiler/method-resolve/method-resolve
  ../compiler/project/runtime-2
  ./p2p)

;; NB: Whichever function exports data end-users / imports from them should make sure to put in a Json array (Scheme list) prepend by the name of the type. And/or we may have a {"": "InteractionAgreement" ...} field with this asciibetically always-first name. Maybe such function belongs to gerbil-poo, too.

(define-type Tokens (MonomorphicObject Nat))

(define-type AgreementOptions
  (Record
   blockchain: [String] ;; e.g. "Cardano KEVM Testnet", as per ethereum_networks.json
   escrowAmount: [(Maybe Tokens) default: (void)] ;; not meaningful for all contracts
   timeoutInBlocks: [Nat]
   maxInitialBlock: [Nat]))

(define-type InteractionAgreement
  (Record
   glow-version: [String] ;; e.g. "Glow v0.0-560-gda782c9 on Gerbil-ethereum v0.0-83-g6568bc6" ;; TODO: have a function to compute that from versioning.ss
   interaction: [String] ;; e.g. "buy_sig#buySig", fully qualified Gerbil symbol
   participants: [(MonomorphicObject Address)] ;; e.g. {Buyer: alice Seller: bob}
   ;; TODO: rename assets to resources
   assets: [(MonomorphicObject Asset)] ;; not just asset names such as "ETH", "CED", "QASCED", "PET", or "QASPET", objects from `lookup-asset`
   parameters: [Json] ;; This Json object to be decoded according to a type descriptor from the interaction (dependent types yay!)
   reference: [(MonomorphicObject Json)] ;; Arbitrary reference objects from each participant, with some conventional size limits on the Json string.
   options: [AgreementOptions] ;; See above
   code-digest: [Digest])) ;; Make it the digest of Glow source code (in the future, including all Glow libraries transitively used)

(define-type AgreementHandshake
  (Record
   agreement: [InteractionAgreement]
   contract-config: [ContractConfig]
   published-data: [Bytes])) ;; Variables published by the first active participant inside the first code block.
;; timer-start = (.@ agreement-handshake agreement options maxInitialBlock)

(define-type IOContext
  (instance Class
    slots: (.o send-handshake: (.o type: (Fun Unit <- AgreementHandshake))
               receive-handshake: (.o type: (Fun AgreementHandshake <-)))))

;; split-interaction-path-name : String -> (values String Symbol)
(def (split-interaction-path-name interaction-str)
  (match (pregexp-match "^([^#]*)#([^#]*)$" interaction-str)
    ([_ path name] (values path (string->symbol name)))
    (else (error "Bad interaction name" interaction-str))))

(def (delete-agreement-handshake)
  (def file (special-file:handshake))
  (displayln "Deleting any old agreement handshake file " file " ...")
  (ignore-errors (delete-file file)))

(def (special-file:handshake) (transient-path "agreement-handshake.json"))
(def (handshake-timeout-in-seconds) (* 15 (ethereum-timeout-in-blocks)))

(def (write-json-handshake handshake port)
  (write-json-ln (json<- AgreementHandshake handshake) port)
  (force-output port))

(def (read-json-handshake port)
  (def handshake-json (json<-port port))
  (when (eof-object? handshake-json)
    (error "read-json-handshake: expected JSON, got EOF from port" port))
  (<-json AgreementHandshake handshake-json))

;; PARTICIPANT RUNTIME

;; TODO: derive the contract from the agreement,
;;       check that the code-digest in the agreement matches
(define-type Runtime
  (.+
   (Record
    role: [Symbol]
    agreement: [InteractionAgreement]
    contract-config: [ContractConfig]
    processed-events: [(List SExp)] ;; : (List LogObjects) ;; ???
    unprocessed-events: [(List SExp)] ;; (List LogObjects) ;; ???
    current-code-block-label: [Symbol]
    current-label: [Symbol]
    current-debug-label: [(Or Symbol False)]
    asset-environment: [(Map Asset <- Symbol)]
    environment: [(Map (Or Any Any) <- Symbol)] ;; (Table (Or DependentPair Any) <- Symbol) ;; TODO: have it always typed???
    block-ctx: [BlockCtx] ;; byte buffer?
    timer-start: [Block]
    first-unprocessed-block: [Block]
    first-unprocessed-event-in-block: [UInt8] ; Index of unprocessed event in a block.
                                              ; NOTE: UInt8 was selected to be reasonably large.
    contract-balances: [(Vector UInt256)]
    program: [Program]
    name: [Symbol]
    consensus-code-generator: [ConsensusCodeGenerator]
    off-chain-channel: [Symbol] ;; [Conn] ;; ???
   )
   {.make: (lambda (role: role
                    agreement: agreement
                    program: program
                    off-chain-channel: off-chain-channel)
             (let* (((values modpath surface-name)
                     (split-interaction-path-name (.@ agreement interaction)))
                    (name
                     (symbol-refer (hash-ref (.@ program compiler-output) 'AlphaEnv)
                                   surface-name))
                    (interaction-info
                     (hash-ref (.@ program interactions) name))
                    (self
                     { role
                       agreement
                       contract-config: #f
                       processed-events: '()
                       unprocessed-events: '()
                       current-code-block-label: (.@ interaction-info initial-code-block-label)  ;; TODO: extract initial code block label from contract compiler output
                       current-label: (.@ program initial-label)
                       current-debug-label: #f
                       asset-environment: (make-hash-table)
                       environment: (make-hash-table)
                       block-ctx: #f
                       timer-start: #f
                       first-unprocessed-block: #f ; Initialized with contract-config
                       first-unprocessed-event-in-block: 0
                       contract-balances: (make-vector (length balance-vars))
                       program
                       name
                       consensus-code-generator: (.call ConsensusCodeGenerator .make program name (.@ agreement options timeoutInBlocks) (.@ agreement assets))
                       off-chain-channel
                       }))
               (set! (.@ self consensus-code-generator)
                 (.call ConsensusCodeGenerator .make program name (.@ agreement options timeoutInBlocks) (.@ agreement assets)))
               (.call ConsensusCodeGenerator .generate (.@ self consensus-code-generator))
               (initialize-environment self)
               self))}))

;; <- Runtime
(def (execute self)
  (with-logged-exceptions ()
    (def ccbl (.@ self current-code-block-label))
    (match (execute-1 self)
      (#f
        (displayln)) ; contract finished
      (exit
        (set! (.@ self current-code-block-label) exit)
        (execute self)))))

;; Execute one step in the interaction. Return value indicates whether
;; we should continue after this step; #f means stop, otherwise the
;; return value is the next code block label.
;;
;; #f | Symbol <- Runtime
(def (execute-1 self)
  (def result
    (if (is-active-participant self)
      (run-active-code-block self)
      (run-passive-code-block self)))
  (set! (.@ self block-ctx) #f)
  (and result (.@ (get-current-code-block self) exit)))

;; Update the stored balance of the contract based on the deposits and withdrawals
;; in the block context.
;;
;; <- Runtime
(def (update-contract-balances self)
  (def sbc (.@ self consensus-code-generator static-block-ctx))
  (def balances (.@ self contract-balances))
  (def (update-balance kv mergefn)
    (def sym (car kv))
    (def amount (cdr kv))
    (def index (.@ (.call StaticBlockCtx .balance-var sbc sym) index))
    (vector-set! balances index (mergefn (vector-ref balances index) amount)))
  (for-each
    (cut update-balance <> +)
    (.@ self block-ctx deposits))
  (for-each
    (cut update-balance <> -)
    (.call BlockCtx .total-withdrawals (.@ self block-ctx))))

;; Bool <- Runtime
(def (is-active-participant self)
  (def current-code-block (get-current-code-block self))
  (equal? (.@ self role) (.@ current-code-block participant)))

;; Watches logs from the first unprocessed block to the timeout block.
;; it return the earliest log,
;; and updates the first-unprocessed-block, unprocessed-event-in-block in Runtime
;; TODO: Return logs in batches, rather than singly. Store unprocessed logs to avoid calling getLogs.
;; TODO: MUCH LATER: present results of speculative execution to user.
;; TODO: (optional) push all the previously processed log objects to the processed list after processing
;; : LogObject <- Runtime
(def (watch self)
  (def-slots (timer-start contract-config first-unprocessed-block first-unprocessed-event-in-block)
    self)
  (def-slots (contract-address) contract-config)
  (let/cc return ; Fetch from logs if no unprocessed events
    (def (callback watch-result)
      (def-slots (next-block next-event log) watch-result)
      (set! (.@ self first-unprocessed-block) next-block)
      (set! (.@ self first-unprocessed-event-in-block) next-event)
      (return log))
    (def from-block first-unprocessed-block)
    (def to-block (+ timer-start (.@ self agreement options timeoutInBlocks)))
    (watch-contract callback contract-address from-block to-block first-unprocessed-event-in-block))
  )

(def (run-passive-code-block/contract self role contract-config)
  (displayln BOLD "\nWaiting for " (.@ (get-current-code-block self) participant) " to make a move ..." END)
  (def new-log-object (watch self))
  (if (eq? new-log-object #!void)
    (let
      ;; No log objects -- this indicates a timeout. The contract will send us
      ;; the escrowed funds, but we need to kick it so that it runs.
      ((address (.@ contract-config contract-address)))
      (displayln RED "Timed out waiting for other participant; claiming escrowed funds..." END)
      (post-transaction
        (call-function
          (get-active-participant self)
          address
          (call-with-output-u8vector
            (lambda (out)
              (publish-frame-data self out)))))
      #f)
    (let ()
      (def log-data (.@ new-log-object data))
      (set! (.@ self timer-start) (.@ new-log-object blockNumber))
      ;; TODO: process the data in the same method?
      (set! (.@ self block-ctx) (.call PassiveBlockCtx .make log-data))
      (interpret-current-code-block self)
      #t)))

(def (interpret-current-code-block self)
  (let (code-block (get-current-code-block self))
    (displayln BOLD "\nExecuting code block " (.@ self current-code-block-label) " ..." END)
    (for ((statement (.@ code-block statements)))
      (interpret-participant-statement self statement))
    (update-contract-balances self)))

(def (passive-participant-handshake self role)
  (nest
   (let (off-chain-channel (.@ self off-chain-channel)))
   (let (agreement-handshake (.call off-chain-channel .receive-handshake self)))
   (begin
     (force-current-outputs))
   (with-slots (agreement contract-config published-data) agreement-handshake)
   (let (block-ctx (.@ self block-ctx)))
   (begin
     (set! (.@ self block-ctx) (.call PassiveBlockCtx .make published-data))
     ;; TODO: Execute contract until first change participant.
     ;; Check that the agreement part matches
     (unless (equal? (json<- InteractionAgreement (.@ self agreement))
                     (json<- InteractionAgreement agreement))
       (DDT agreements-mismatch:
            InteractionAgreement (.@ self agreement)
            InteractionAgreement agreement)
       (error "agreements don't match" (.@ self agreement) agreement))
     (set! (.@ self timer-start) (.@ agreement options maxInitialBlock))
     (set! (.@ self first-unprocessed-block) (.@ contract-config creation-block))
     (void))
   (let (create-pretx (prepare-create-contract-transaction self))
     (verify-contract-config contract-config create-pretx)
     (set! (.@ self contract-config) contract-config)))
  #t)

;; Runs the passive participant's side of the interaction. Return value
;; indicates whether we should continue executing (#t) or stop now (#f).
;;
;; Bool <- Runtime
(def (run-passive-code-block self)
  (def role (.@ self role))
  ;; if the contract has not been created yet, do handshake first
  (when (not (.@ self contract-config))
    (passive-participant-handshake self role))
  (run-passive-code-block/contract self role (.@ self contract-config)))

;; Run the active participant's side of the interaction. Return value
;; indicates whether we should continue executing (#t) or stop now (#f).
;;
;; Bool <- Runtime
(def (run-active-code-block self)
  (def role (.@ self role))
  (set! (.@ self block-ctx) (.call ActiveBlockCtx .make))
  ;; if the contract has not been created yet, create it first,
  ;; before running `interpret-current-code-block`
  ;; TODO: as an optimization, it could be possible to run interpret-current-code-block
  ;;       before this, in the cases where it doesn't have side-effects such as withdraws
  ;;       call it first-transaction-optimization
  (when (not (.@ self contract-config))
   (let ()
    (deploy-contract self)
    (def contract-config (.@ self contract-config))
    (def agreement (.@ self agreement))
    (def published-data (get-output-u8vector (.@ self block-ctx outbox)))
    (def handshake (.new AgreementHandshake agreement contract-config published-data))
    (def off-chain-channel (.@ self off-chain-channel))
    (.call off-chain-channel .send-handshake self handshake)))
  (publish-frame-data self (.@ self block-ctx outbox))
  (interpret-current-code-block self)
  ;; TODO: Verify asset transfers using previous transaction and balances
  ;; recorded in Message's asset-transfer table during interpretation. Probably
  ;; requires getting TransactionInfo using the TransactionReceipt.
  (def contract-address (.@ self contract-config contract-address))
  (approve-deposits self contract-address)
  (def message-pretx
       (prepare-call-function-transaction
         self
         contract-address
         (.@ self block-ctx outbox)))
  (def new-tx-receipt (post-transaction message-pretx))
  (set! (.@ self timer-start) (.@ new-tx-receipt blockNumber))
  (set! (.@ self first-unprocessed-block) (1+ (.@ new-tx-receipt blockNumber)))
  (set! (.@ self first-unprocessed-event-in-block) 0)
  #t)

;; Pre-approve any deposits that the current block will need to perform
;; when we invoke the consensus.
;;
;; <- Runtime Address
(def (approve-deposits self contract-address)
  (def sbc (.@ self consensus-code-generator static-block-ctx))
  (for-each
    (lambda (deposit)
      (def asset-sym (car deposit))
      (def asset (.call StaticBlockCtx .get-asset sbc asset-sym))
      (def amount (cdr deposit))
      (.call asset .approve-deposit! (get-active-participant self) contract-address amount))
    (.@ self block-ctx deposits)))

;; Nat <- Runtime
(def (native-asset-deposit self)
  (def sbc (.@ self consensus-code-generator static-block-ctx))
  (def deposits
    (filter
      (lambda (deposit)
        (def asset-sym (car deposit))
        (native-asset? (.call StaticBlockCtx .get-asset sbc asset-sym)))
      (.@ self block-ctx deposits)))
  (apply + (map cdr deposits)))

;; Sexp <- State
(def (sexp<-state state) (map (match <> ([t . v] (sexp<- t v))) state))

;; TODO: include type output, too, looked up in type table.
;; <- Runtime Symbol Value
(def (add-to-environment self name value)
  (hash-put! (.@ self environment) name value))

;; PreTransaction <- Runtime Block
(def (prepare-create-contract-transaction self)
  (def sender-address (get-active-participant self))
  (def current-code-block-label (.@ self current-code-block-label))
  (def code-block (get-current-code-block self))
  (def participant (.@ code-block participant))
  (def initial-state
    (create-frame-variables
     self
     (.@ self agreement options maxInitialBlock)
     current-code-block-label
     participant))
  (def initial-state-digest
    (digest-product-f initial-state))
  (def contract-bytes
    (stateful-contract-init initial-state-digest (.@ self consensus-code-generator bytes)))
  (create-contract sender-address contract-bytes
    value: (native-asset-deposit self)))

;; PreTransaction <- Runtime Block
(def (deploy-contract self)
  (def role (.@ self role))
  (def timer-start (.@ self agreement options maxInitialBlock))
  (set! (.@ self timer-start) timer-start)
  (def pretx (prepare-create-contract-transaction self))

  ;; Pick a nonce now, and pre-compute the contract address, so we
  ;; can invoke approve-deposits before we create the contract. The
  ;; same transaction that creates the contract could also deposit,
  ;; so after creation it is too late.
  ;;
  ;; WARNING: this means there is a race condition where, if the
  ;; participant's address is being used concurrently by some other
  ;; process, we could end up with the wrong contract address.
  ;;
  ;; The tokens will still be recoverable in this case; approve-deposits
  ;; only *approves* transfers, but does not actually perform them,
  ;; so as long as the other contract doesn't do something with them,
  ;; we should be able to just change the approval after the fact.
  ;;
  ;; ...but glow will throw an error, and this transaction will fail.
  ;;
  ;; In the future, we should avoid this by adjusting the compiler to
  ;; split creation and the first part of the interaction into separate
  ;; transactions, so we don't need to know the contract's address before
  ;; we create it -- we can create it and then approve the transfers
  ;; afterwards. One complication is that right now we don't have to pay
  ;; gas for all of the instructions that would be in the first transaction,
  ;; since we just pre-compute the state at the end of that transaction
  ;; and store it. We should try to maintain this property somehow.
  (unless (.@ pretx nonce)
    (set! (.@ pretx nonce) (next-nonce (.@ pretx from))))
  (def contract-address (transaction-to pretx))
  (approve-deposits self contract-address)

  (def receipt (post-transaction pretx))
  (def contract-config (contract-config<-creation-receipt receipt))
  (verify-contract-config contract-config pretx)
  (set! (.@ self contract-config) contract-config)
  (set! (.@ self first-unprocessed-block) (.@ contract-config creation-block)))

;; <- Runtime BytesOutputPort
;;
;; Write frame data to `out`, to be sent to the contract for restoration.
(def (publish-frame-data self out)
  (assert! (symbol? (.@ self current-code-block-label)))
  (def frame-variables
    (create-frame-variables
      self
      (.@ self timer-start)
      (.@ self current-code-block-label)
      (.@ self role)))
  (def frame-variable-bytes (marshal-product-f frame-variables))
  (def frame-length (bytes-length frame-variable-bytes))
  (marshal UInt16 frame-length out)
  (marshal-product-to frame-variables out))

;; See gerbil-ethereum/evm-runtime.ss for spec.
;; PreTransaction <- Runtime Message.Outbox Block Address
(def (prepare-call-function-transaction self contract-address out)
  (marshal UInt8 1 out)
  (def message-bytes (get-output-u8vector out))
  (def sender-address (get-active-participant self))
  (call-function sender-address contract-address message-bytes
    ;; default gas value should be (void), i.e. ask for an automatic estimate,
    ;; unless we want to force the TX to happen, e.g. so we can see the failure in Remix
    ;; gas: 1000000 ;; XXX ;;<=== DO NOT COMMIT THIS LINE UNCOMMENTED
    value: (native-asset-deposit self)))

;; CodeBlock <- Runtime
(def (get-current-code-block self)
    (def participant-interaction
      (get-interaction (.@ self program) (.@ self name) (.@ self role)))
    (hash-get participant-interaction (.@ self current-code-block-label)))

;; TODO: map alpha-converted names to names in original source when displaying to user
;;       using the alpha-back-table
;; <- Runtime
(def (initialize-environment self)
  (def inter (hash-ref (.@ self program interactions) (.@ self name)))
  (def alba (hash-ref (.@ self program compiler-output) 'albatable.sexp))
  (def agreement (.@ self agreement))
  (def participants (.@ agreement participants))
  (for (participant-name (filter symbol? (hash-keys (.@ inter specific-interactions))))
    (def participant-surface-name (hash-ref alba participant-name))
    (add-to-environment self participant-name (.ref participants participant-surface-name)))
  (def assets (.@ agreement assets))
  (for (asset-name (.@ inter asset-names))
    (def asset-value (.ref assets asset-name))
    (hash-put! (.@ self asset-environment) asset-name asset-value))
  (def parameters (.@ agreement parameters))
  (for (parameter-name (.@ inter parameter-names))
    (def parameter-surface-name (hash-ref alba parameter-name))
    (def parameter-json-value (json-object-ref parameters parameter-surface-name))
    (def parameter-type (lookup-type (.@ self program) parameter-name))
    (def parameter-value (<-json parameter-type parameter-json-value))
    (add-to-environment self parameter-name parameter-value)))

;; TODO: make sure everything always has a type ???
;; Any <- Runtime
(def (reduce-expression self expression)
  (cond
   ((symbol? expression)
    (match (hash-ref/default
            (.@ self environment) expression
            (cut error "variable missing from execution environment" expression))
      ([type . value]
       value)
      (value
        value)))
   ((boolean? expression) expression)
   ((string? expression) (string->bytes expression))
   ((bytes? expression) expression)
   ((integer? expression) expression)
   ;; TODO: reduce other trivial expressions
   (else
    expression)))

;; Symbol <- Runtime
(def (get-active-participant self)
  (def environment (.@ self environment))
  (hash-get environment (.@ self role)))

;; Bytes <- (List DependentPair)
(def (marshal-product-f fields)
  (call-with-output-u8vector (λ (out)
    (marshal-product-to fields out))))
;; <- (List DependentPair) BytesOutputPort
(def (marshal-product-to fields port)
  (for ((p fields))
    (with (([t . v] p)) (marshal t v port))))

;; : Digest <- (List DependentPair)
(def (digest-product-f fields)
  (digest<-bytes (marshal-product-f fields)))

;; : <- Runtime ProjectStatement
(def (interpret-participant-statement self statement)
  (displayln statement)
  (match statement

    (['set-participant new-participant]
      ;; Since the contract has already been separated into transaction boundaries,
      ;; the participant doesn't need to do anything here, since the active participant
      ;; is already known.
     (void))

    (['add-to-deposit ['@record [asset-symbol amount-variable]]]
     (let
       ((this-participant (get-active-participant self))
        (amount (reduce-expression self amount-variable)))
       (.call BlockCtx .add-to-deposit (.@ self block-ctx) this-participant asset-symbol amount)))

    (['expect-deposited ['@record [asset-symbol amount-variable]]]
     (let
       ((this-participant (get-active-participant self))
        (amount (reduce-expression self amount-variable)))
       (.call BlockCtx .add-to-deposit (.@ self block-ctx) this-participant asset-symbol amount)))

    (['participant:withdraw address-variable ['@record [asset-symbol price-variable]]]
     (let ((address (reduce-expression self address-variable))
           (price (reduce-expression self price-variable)))
       (.call BlockCtx .add-to-withdraw (.@ self block-ctx) address asset-symbol price)))

    (['add-to-publish ['quote publish-name] variable-name]
     (let ((publish-value (reduce-expression self variable-name))
           (publish-type (lookup-type (.@ self program) variable-name)))
       (.call ActiveBlockCtx .add-to-published (.@ self block-ctx)
              publish-name publish-type publish-value)))

    (['def variable-name expression]
     (let
       ((variable-value (interpret-participant-expression self expression)))
       (add-to-environment self variable-name variable-value)))

    (['require! variable-name]
     (match (reduce-expression self variable-name)
       (#t (void))
        ;; TODO: include debugging information when something fails!
       (#f
        (error "Assertion failed"))
       (n
        (error "Assertion failed, " variable-name " is not a Boolean."))))

    (['return ['@tuple]]
      (void))

    (['return expression]
      (interpret-participant-expression self expression))

    (['@label name]
     (set! (.@ self current-label) name))
    (['@debug-label name]
     (set! (.@ self current-debug-label) name))

    (['switch variable-name cases ...]
      (let* ((variable-value (reduce-expression self variable-name))
             (matching-case (find (λ (case) (equal? (reduce-expression self (car case)) variable-value)) cases)))
        (for (case-statement (cdr matching-case))
          (interpret-participant-statement self case-statement))))))

(def (interpret-participant-expression self expression)
  (match expression

    (['expect-published ['quote publish-name]]
     (let (publish-type (lookup-type (.@ self program) publish-name))
       (.call PassiveBlockCtx .expect-published (.@ self block-ctx) publish-name publish-type)))

    (['@app 'isValidSignature address-variable digest-variable signature-variable]
     (let
       ((address (reduce-expression self address-variable))
        (digest (reduce-expression self digest-variable))
        (signature (reduce-expression self signature-variable)))
       (isValidSignature address digest signature)))

    (['@app '< a b]
     (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (< av bv)))

    (['@app '+ a b]
     (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (+ av bv)))

    (['@app '- a b]
     (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (- av bv)))

    (['@app '* a b]
     (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (* av bv)))

    (['@app 'bitwise-xor a b]
     (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (bitwise-xor av bv)))

    (['@app 'bitwise-and a b]
     (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (bitwise-and av bv)))

    (['@app 'mod a b]
      (let
       ((av (reduce-expression self a))
        (bv (reduce-expression self b)))
       (modulo av bv)))

    (['@app 'randomUInt256]
     (randomUInt256))

    ;; WARNING: This does not support re-entrancy!
    ;; TODO: Enable re-entrancy.
    (['@app name . argument-names]
      (let* ((small-function (hash-get (.@ self program small-functions) name))
             (zipped-arguments (map cons argument-names (.@ small-function arguments))))
        (unless small-function
          (error "Unknown function " name))
        (for ((zipped-argument zipped-arguments))
          (add-to-environment self (cdr zipped-argument) (reduce-expression self (car zipped-argument))))
        (let/cc return
          (for ((statement (.@ small-function body)))
            (let (result (interpret-participant-statement self statement))
              (when (equal? (car statement) 'return) (return result)))))))

    (['@tuple . es]
     (list->vector
      (for/collect ((e es))
        (reduce-expression self e))))

    (['digest . es]
     (digest
      (for/collect ((e es))
        (cons (lookup-type (.@ self program) e)
              (reduce-expression self e)))))

    (['sign digest-variable]
     (let ((this-participant (get-active-participant self))
           (digest (reduce-expression self digest-variable)))
       (make-message-signature (secret-key<-address this-participant) digest)))

    (['input 'Nat tag]
     (let ((tagv (reduce-expression self tag)))
       (interaction-input UInt256 tagv)))

    (['== a b]
      (let ((av (reduce-expression self a))
            (bv (reduce-expression self b)))
        (equal? av bv)))

    (else
      (reduce-expression self expression))))

;; Convert a list of (variable value) items into a list of
;; (type value) pairs, and check that the list corresponds to
;; the variables defined by define-consecutive-addresses, between
;; addresses start and end.
(def (frame-variables/consecutive-addresses start end items)
  (def vars (map car items))
  (def vals (map cadr items))
  (def names (map (lambda (v) (.@ v name)) vars))
  (def types (map (lambda (v) (.@ v type)) vars))
  (def addresses (map (lambda (v) (.@ v address)) vars))
  (check-consecutive-addresses start end names types addresses)
  (map cons types vals))

;; check-consecutive-addresses : Int Int [Listof Sym] [Listof Type] [Listof Int] -> Void
(def (check-consecutive-addresses start end names types addresses)
  (def i
    (for/fold (i start) ((n names) (t types) (a addresses))
      (unless (= i a)
        (error (format
                 (string-append
                   "check-consecutive-addresses: variable ~a was found at offset ~a, "
                   "but its expected address is ~a")
                 n i a)))
      (+ i (.@ t .length-in-bytes))))
  (unless (= i end)
    (error (format
             (string-append
               "check-consecutive-addresses: ending offset was incorrect; "
               "expected ~a but got ~a") end i))))

;; : Frame <- Runtime Block Symbol Symbol
(def (create-frame-variables self timer-start code-block-label code-block-participant)
  (assert! (symbol? code-block-label))
  (def consensus-code-generator (.@ self consensus-code-generator))
  (def checkpoint-location
    (hash-kref (.@ consensus-code-generator labels) (make-checkpoint-label (.@ self name) code-block-label)))
  ;TODO: delete if not used anywhere?
  ;(def active-participant-offset
  ;  (lookup-variable-offset consensus-code-generator code-block-label code-block-participant))
  (def balances (vector->list (.@ self contract-balances)))
  (def live-variables (lookup-live-variables (.@ self program) (.@ self name) code-block-label))
  ;; TODO: ensure keys are sorted in both hash-values
  (append
   (frame-variables/consecutive-addresses frame@ params-start@
    (append
      [[pc-var checkpoint-location]]
      (map list balance-vars balances)
      [[timer-start-var timer-start]]))
   ;; [UInt16 . active-participant-offset]
   ;; TODO: designate participant addresses as global variables that are stored outside of frames
   (map
     (λ (variable-name)
       (def variable-type (lookup-type (.@ self program) variable-name))
       (def variable-value (hash-get (.@ self environment) variable-name))
       [variable-type . variable-value])
     (sort live-variables symbol<?))))

(def (interaction-input t s)
  (def env-input (ignore-errors (getenv "INPUT")))
  (match env-input
    ((? string?)
      ;; FIXME: This does not allow for multiple inputs.
     (<-json t (string->json-object env-input)))
    (#f
     (printf (string-append CYAN "\n~a [~s]\n" END) (if (u8vector? s) (bytes->string s) s) (.@ t sexp))
     (display (string-append CYAN "> " END))
     (def result (<-json t (read-json (current-input-port))))
     (displayln)
     result)))


;; ---------------------------------------------------
;; ------------------ Off-chain communication channels
;; ---------------------------------------------------

;; An OffChainChannelType is a Poo object with the method:
;;   .make : (Fun ConstructorInputs ... -> OffChainChannel)

;; An OffChainChannel is a Poo object with the methods:
;;   .send-agreement : (Fun InteractionAgreement -> Void)
;;   .try-receive-agreement : (Fun -> (Or #f InteractionAgreement))
;;   .receive-agreement : (Fun -> InteractionAgreement)
;;   .send-handshake : (Fun Runtime AgreementHandshake -> Void)
;;   .receive-handshake : (Fun Runtime -> AgreementHandshake)
;;   .close : (Fun -> Any)

;; Possible usage sequence of OffChainChannel,
;; assuming that A is the first to start and the first active participant:
;;             A                               B
;;             |                               |
;;           .make                           .make
;;             |                               |
;; .try-receive-agreement failure              |
;;             |                               |
;;      .send-agreement ----------> .try-receive-agreement success
;;             |                               |
;;      .send-handshake ------------> .receive-handshake
;;             |                               |
;;          .close                          .close
;; The agreement send/receive might be reversed if B is the first to start,
;; The handshake send/receive might be reversed if B is the first active participant.
;; If they start near the same time, more .try-receive-agrement failures before eventual success:
;;             A                               B
;;             |                               |
;;           .make                           .make
;;             |                               |
;; .try-receive-agreement failure   .try-receive-agreement failure
;;             |                               |
;; .try-receive-agreement failure              |
;;             |                               |
;;      .send-agreement ----------> .try-receive-agreement success
;;             |                               |
;;      .send-handshake ------------> .receive-handshake
;;             |                               |
;;          .close                          .close
;; The --wait-for-agreement option triggers .receive-agreement instead of .try-receive-agreement,
;; and prevents that side from prompting to generate an agreement to send.

;; ------------------ Channel types

(define-type (IoChannel self [])
  .make: (lambda ()
    (assert! (input-port? (current-input-port)))
    { .try-receive-agreement: (lambda () #f)

      .receive-agreement: (lambda ()
        (displayln MAGENTA "Waiting for agreement via stdin ...")
        (def agreement-json (json<-port (current-input-port)))
        (def agreement (<-json InteractionAgreement agreement-json))
        agreement)

      .receive-handshake: (lambda (runtime)
        (displayln MAGENTA "Waiting for handshake via stdin ..." END)
        (displayln MAGENTA "\nPaste below the handshake sent by the other participant:" END)
        (read-json-handshake (current-input-port)))

      .send-agreement: (lambda (agreement)
        (displayln MAGENTA "One line command for other participants to generate the same agreement:" END)
        (def agreement-string (string<-json (json<- InteractionAgreement agreement)))
        (def escaped-agreement-string (escape-agreement-string/shell agreement-string))
        (def full-cmd-string (string-append "glow start-interaction --agreement " escaped-agreement-string))
        (displayln full-cmd-string)
        (force-output))

      .send-handshake: (lambda (runtime handshake)
        (displayln MAGENTA "\nSend the handshake below to the other participant:" END)
        (write-json-handshake handshake (current-output-port)))

      .close: (lambda () #f)
    })
  )

(define-type (IoSpecialFileChannel self [])
  .make: (lambda ()
    (delete-agreement-handshake)
    (def io-channel (.call IoChannel .make))
    { .try-receive-agreement: (.@ io-channel .try-receive-agreement)
      .receive-agreement: (.@ io-channel .receive-agreement)
      .send-agreement: (.@ io-channel .send-agreement)

      .receive-handshake:
      (lambda (runtime)
        (def file (special-file:handshake))
        (def deadline (+ (current-unix-time) (handshake-timeout-in-seconds)))
        (displayln "Waiting for agreement handshake file " file " ...")
        (until (file-exists? file)
          (when (> (current-unix-time) deadline)
            (displayln "Timeout while waiting for handshake!")
            (error "Timeout while waiting for handshake"))
          (thread-sleep! 1))
        (<-json AgreementHandshake (read-file-json file)))

      .send-handshake:
      (lambda (runtime handshake)
        (def file (special-file:handshake))
        (displayln "Writing agreement handshake to file " file " ...")
        (create-directory* (path-parent file))
        (write-file-json (special-file:handshake) (json<- AgreementHandshake handshake)))

      .close:
      (lambda ()
        (delete-agreement-handshake)
        (.call io-channel .close))
    })
  )

(define-type (TcpChannel self [])
  .make:
  (lambda (tcp-options)
    { 
      .send-agreement:
      (lambda (agreement)
        (displayln MAGENTA "Sending agreement via tcp..." END)
        (def listener (tcp-listen (or (json-object-get tcp-options "listen") 10333)))
        (def port (tcp-accept listener))
        (begin0
          (write-json-ln (json<- InteractionAgreement agreement) port)
          (force-output port)
          (close-port port)
          (tcp-close listener)
          (displayln MAGENTA "Done sending agreement." END)))

      .try-receive-agreement:
      (lambda ()
        (displayln MAGENTA "Trying briefly to receive agreement via tcp..." END)
        (def port
          (try-tcp-connect
            (or (json-object-get tcp-options "connect") "localhost:10333")
            (lambda () #f)))
        (and
          port
          (begin0
            (<-json InteractionAgreement (json<-port port))
            (close-input-port port))))

      .receive-agreement:
      (lambda ()
        (displayln MAGENTA "Waiting to receive agreement via tcp..." END)
        (def port
          (tcp-connect/retry
            (or (json-object-get tcp-options "connect") "localhost:10333")
            (lambda ()
              (displayln "Timeout while waiting for agreement!")
              (error "Timeout while waiting for agreement"))
            retry-window: 1
            max-window: 10
            max-retries: 10))
        (begin0
          (<-json InteractionAgreement (json<-port port))
          (close-output-port port)
          (close-input-port port)))

      .send-handshake:
      (lambda (runtime handshake)
        (displayln "Writing agreement handshake to tcp server port ...")
        (def listener (tcp-listen (or (json-object-get tcp-options "listen") 10333)))
        (def port (tcp-accept listener))
        (begin0
          (write-json-handshake handshake port)
          (close-port port)
          (tcp-close listener)
          (displayln "Done writing agreement handshake.")))

      .receive-handshake:
      (lambda (runtime)
        (displayln "Waiting for agreement handshake from tcp client port ...")
        (def port
          (tcp-connect/retry
            (or (json-object-get tcp-options "connect") "localhost:10333")
            (lambda ()
              (displayln "Timeout while waiting for handshake!")
              (error "Timeout while waiting for handshake"))
            retry-window: 1
            max-window: 10
            max-retries: 10))
        (begin0
          (read-json-handshake port)
          (close-output-port port)
          (close-input-port port)))

      .close: (lambda () #f)
    })
  )

(define-type (IoTcpChannel @ [])
  .make:
  (lambda (tcp-options)
    (def io-channel (.call IoChannel .make))
    (def tcp-channel (.call TcpChannel .make tcp-options))
    { .try-receive-agreement: (.@ io-channel .try-receive-agreement)
      .receive-agreement: (.@ io-channel .receive-agreement)
      .send-agreement: (.@ io-channel .send-agreement)

      .send-handshake: (.@ tcp-channel .send-handshake)
      .receive-handshake: (.@ tcp-channel .receive-handshake)

      .close:
      (lambda ()
        (.call io-channel .close)
        (.call tcp-channel .close)) }))

(define-type (Libp2pChannel @ [])
    .make: (lambda (my-nickname host-address contacts circuit-relay-address pubsub-node)
       (let ()

         ;; ------------ Libp2p channel buffer setup

         (def buffer (make-channel 10)) ;; TODO: Do we need a larger buffer?

         (def (poll-buffer (t 2)) ; poll every 2s by default
           (def res (channel-try-get buffer))
           (or res
             (begin (thread-sleep! t)
                    (poll-buffer t))))

         (def (push-to-buffer s)
           (def received-data (chat-reader s))
           ; NOTE: This blocks indefinitely if channel buffer is full
           (channel-put buffer received-data)
           (stream-close s))


         ;; ------------ Libp2p listening thread setup


         ;; Ensure libp2p-daemon client is running
         (displayln "Starting libp2p client")

         ;; If the a host address is specified, use that, if not, use default host address
         (def libp2p-client
           (if host-address
             (open-libp2p-client host-addresses: host-address wait: 10 options: ["-q" "-pubsub" "-connManager"])
             (error "Default host-address has not been implemented yet")))

         ;; Get and Broadcast identity
         (def self (libp2p-identify libp2p-client))
         (for (p (peer-info->string* self))

           (displayln "I am " p))

         ;; Find your Blockchain Addr from your Nickname
         (def my-0xaddr (0x<-address (address<-nickname my-nickname)))


         ;;initialize the pubsub for peer discovery, if default value is #f throw error
         (defvalues (sub cancel pubsub-listen-thread)
           (if pubsub-node
             (connect-to-multiaddr-pubsub pubsub-node: pubsub-node c: libp2p-client my-0xaddr: my-0xaddr)
             (error "Default pubsub-node connection has not been implemented yet")))

         ;;connect to the circuit-relay, if default value is #f throw error
         (def circuit-relay
           (if circuit-relay-address
             (string->peer-info circuit-relay-address)
             (error "Default circuit-relay connection has not been implemented yet")))

         (libp2p-connect libp2p-client circuit-relay)
         
         (def listening-thread
           (begin
            (displayln "Listening for messages...")
            (spawn libp2p-listen libp2p-client [chat-proto] push-to-buffer)))

         ;;----------------------------------------------------------

         (def dest-address #f)

         { libp2p-client
           poll-buffer
           push-to-buffer
           _listening-thread: listening-thread
           pubsub-listen-thread
           sub
           cancel
           circuit-relay

           .send-agreement: (lambda (agreement)
             (displayln MAGENTA "Sending agreement to multiaddr..." END)
             (def agreement-string (string<-json (json<- InteractionAgreement agreement)))

             ;;Get the other participant from the agreement
             (set! dest-address
                  (hash-find (lambda (key value)
                               (if (not (equal? my-0xaddr (0x<-address value)))
                                 (0x<-address value)))
                             (hash<-object (.@ agreement participants))))
             (displayln "getting peerID")
             (def dest-peerID (get-peerID-from-pubsub sub
                                                      libp2p-client
                                                      dest-address
                                                      10)) ;;Multiaddr from the Eth addr using pubsub BLOCKS UNTIL ADDRESS IS FOUND Or timeout
             (displayln "peerID obtained")
             (dial-and-send-contents libp2p-client
                                     (string-join (list (peer-info->string circuit-relay) dest-peerID) "/p2p-circuit/p2p/")
                                     agreement-string)
             (displayln "peer dialed")
             (displayln)
             (force-output))

           .send-handshake: (lambda (_runtime handshake)

             (displayln MAGENTA "Sending handshake to multiaddr..." END)
             (def handshake-string (string<-json (json<- AgreementHandshake handshake)))


             (def dest-peerID (get-peerID-from-pubsub sub
                                                     libp2p-client
                                                     dest-address
                                                     10))

             (dial-and-send-contents libp2p-client
                                     (string-join (list (peer-info->string circuit-relay) dest-peerID) "/p2p-circuit/p2p/")
                                     handshake-string)
             (displayln)
             (force-output))

           .receive-handshake: (lambda (_runtime) ;TODO: Make sure you are receiving messages only from people you want to talk to
             (displayln MAGENTA "Listening for handshake via libp2p ..." END)
             (def handshake-str (poll-buffer))
             (displayln MAGENTA "Received handshake" END)
             (def handshake (<-json AgreementHandshake (json<-string handshake-str)))
             handshake)

           .try-receive-agreement: (lambda () #f)

           .receive-agreement: (lambda ()
             (displayln MAGENTA "Listening for agreement via libp2p ..." END)
             (def agreement-str (poll-buffer))
             (displayln MAGENTA "Received agreement" END)
             (def agreement (<-json InteractionAgreement (json<-string agreement-str)))
             agreement)

            .close: (lambda () (stop-libp2p-daemon!) (cancel) (thread-abort! (car pubsub-listen-thread)))
           })))


;; ------------------ Initialize Off-chain channels


(def (init-off-chain-channel options)
  (def off-chain-channel-selection (hash-get options 'off-chain-channel-selection))
  (match off-chain-channel-selection
    ('stdio 
     (let ()
       (def tcp-options (hash-ref options 'tcp-options))
       (cond (tcp-options (.call IoTcpChannel .make tcp-options))
             (else        (.call IoChannel .make)))))
    ('tcp 
     (let ()
       (def tcp-options (hash-ref options 'tcp-options))
       (.call TcpChannel .make tcp-options)))
    ('libp2p (let ()
     (def my-nickname (hash-ref options 'my-nickname))
     (def host-address (hash-ref options 'host-address))
     (def contacts (hash-ref options 'contacts))
     (def circuit-relay-address (hash-ref options 'circuit-relay-address))
     (def pubsub-node (hash-ref options 'pubsub-node))
     (.call Libp2pChannel .make my-nickname host-address contacts circuit-relay-address pubsub-node)))
    (else (error "Invalid off-chain channel selection"))))


;; ------------------ Misc


;; TODO: Generalize this for escaping arbitrary strings in the shell, upstream to `gerbil-utils'.
;; NOTE: It currently does not correctly escape things for the shell. E.g:
;; "$(rm -rf /) ''" would be passed through unchanged, since it contains a single quote.
;; If you got rid of that first case,
;; then "'$(rm -rf /)'" would still slip by the escaping in the second case;
;; due to the way shell escaping works,
;; you can unquote back into an interpreted context.
;; So you also need to substitute out any single quotes in the middle of the string.
(def (escape-agreement-string/shell agreement-string)
  (if (string-contains agreement-string "'")
    agreement-string
    (string-append "'" agreement-string "'")))


(def (lookup-contact nickname: nickname contacts: contacts)
  ;; (for-each (lambda (contact) (displayln (.@ contact name))) contacts)
  (find (lambda (contact) (equal? (.@ contact name) nickname)) contacts))
