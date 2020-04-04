(defdata Hand Rock Paper Scissors)
(def inputHand (λ (tag) (def x : Hand (input Hand tag)) x))
(def NatToHand
     (λ ((x0 : int))
        (def tmp0 (and (@app <= 0 x0) (block (def tmp (@app < x0 3)) (def tmp1 (and tmp)) (and tmp1))))
        (require! tmp0)
        (if (@app = x0 0) Rock (if (@app = x0 1) Paper Scissors))))
(def HandToNat (λ ((x1 : Hand)) (switch x1 (Rock 0) (Paper 1) (Scissors 2))))
(defdata Outcome B_Wins Draw A_Wins)
(def inputOutcome (λ (tag0) (def x2 : Outcome (input Outcome tag0)) x2))
(def NatToOutcome
     (λ ((x3 : int))
        (def tmp3 (and (@app <= 0 x3) (block (def tmp2 (@app < x3 3)) (def tmp4 (and tmp2)) (and tmp4))))
        (require! tmp3)
        (if (@app = x3 0) B_Wins (if (@app = x3 1) Draw A_Wins))))
(def OutcomeToNat (λ ((x4 : Outcome)) (switch x4 (B_Wins 0) (Draw 1) (A_Wins 2))))
(def winner
     (λ ((handA : Hand) (handB : Hand))
        :
        Outcome
        (def tmp5 (@app HandToNat handA))
        (def tmp6 (@app HandToNat handB))
        (def tmp7 (@app - 4 tmp6))
        (def tmp8 (@app mod tmp7 3))
        (def tmp9 (@app + tmp5 tmp8))
        (@app NatToOutcome tmp9)))
(@interaction
 ((@list A B))
 (def rockPaperScissors
      (λ (wagerAmount)
         (@ A (def handA0 (@app inputHand "First player, pick your hand")))
         (@ A (def salt (@app randomUInt256)))
         (@ A (@verifiably (def commitment (digest salt handA0))))
         (@ A (publish! commitment))
         (@ A (deposit! wagerAmount))
         (@ B (def handB0 (@app inputHand "Second player, pick your hand")))
         (@ B (publish! handB0))
         (@ B (deposit! wagerAmount))
         (@ A (publish! salt handA0))
         (verify! commitment)
         (def outcome (@app winner handA0 handB0))
         (switch outcome
                 (A_Wins (def tmp10 (@app * 2 wagerAmount)) (withdraw! A tmp10))
                 (B_Wins (def tmp11 (@app * 2 wagerAmount)) (withdraw! B tmp11))
                 (Draw (withdraw! A wagerAmount) (withdraw! B wagerAmount)))
         outcome)))
