(hash (* (type:arrow (@list (type:name 'Int) (type:name 'Int)) (type:name 'Int)))
      (+ (type:arrow (@list (type:name 'Int) (type:name 'Int)) (type:name 'Int)))
      (- (type:arrow (@list (type:name 'Int) (type:name 'Int)) (type:name 'Int)))
      (A (type:name 'Participant))
      (A_Wins (type:name 'Outcome0))
      (B (type:name 'Participant))
      (B_Wins (type:name 'Outcome0))
      (Draw (type:name 'Outcome0))
      (Hand1 (type:record
              (symdict ('toNat (type:arrow (@list (type:name 'Hand0)) (type:name-subtype 'Nat (type:name 'Int))))
                       ('ofNat (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Hand0)))
                       ('input (type:arrow (@list (type:name 'Bytes)) (type:name 'Hand0))))))
      (Outcome1
       (type:record
        (symdict ('toNat (type:arrow (@list (type:name 'Outcome0)) (type:name-subtype 'Nat (type:name 'Int))))
                 ('ofNat (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Outcome0)))
                 ('input (type:arrow (@list (type:name 'Bytes)) (type:name 'Outcome0))))))
      (Paper (type:name 'Hand0))
      (Rock (type:name 'Hand0))
      (Scissors (type:name 'Hand0))
      (commitment (type:name 'Digest))
      (handA (type:name 'Hand0))
      (handA0 (type:name 'Hand0))
      (handB (type:name 'Hand0))
      (handB0 (type:name 'Hand0))
      (mod (type:arrow
            (@list (type:name 'Int) (type:name-subtype 'Nat (type:name 'Int)))
            (type:name-subtype 'Nat (type:name 'Int))))
      (outcome (type:name 'Outcome0))
      (randomUInt256 (type:arrow (@list) (type:name-subtype 'Nat (type:name 'Int))))
      (rockPaperScissors
       (type:arrow (@list (type:name 'Participant) (type:name 'Participant) (type:name 'Int)) (type:name 'Outcome0)))
      (salt (type:name-subtype 'Nat (type:name 'Int)))
      (tag (type:name 'Bytes))
      (tag0 (type:name 'Bytes))
      (wagerAmount (type:name 'Int))
      (winner (type:arrow (@list (type:name 'Hand0) (type:name 'Hand0)) (type:name 'Outcome0)))
      (x (type:name 'Hand0))
      (x0 (type:name 'Hand0))
      (x1 (type:name-subtype 'Nat (type:name 'Int)))
      (x2 (type:name 'Outcome0))
      (x3 (type:name 'Outcome0))
      (x4 (type:name-subtype 'Nat (type:name 'Int)))
      (0 (type:name-subtype 'Nat (type:name 'Int)))
      (1 (type:name-subtype 'Nat (type:name 'Int)))
      (2 (type:name-subtype 'Nat (type:name 'Int)))
      (3 (type:name-subtype 'Nat (type:name 'Int)))
      (4 (type:name-subtype 'Nat (type:name 'Int)))
      ("First player, pick your hand" (type:name 'Bytes))
      ("Second player, pick your hand" (type:name 'Bytes))
      ((== commitment (digest (@tuple salt handA0))) (type:name 'Bool))
      ((@app * 2 wagerAmount) (type:name 'Int))
      ((@app + (@app (@dot Hand1 toNat) handA) (@app - 4 (@app (@dot Hand1 toNat) handB))) (type:name 'Int))
      ((@app - 4 (@app (@dot Hand1 toNat) handB)) (type:name 'Int))
      ((@app mod (@app + (@app (@dot Hand1 toNat) handA) (@app - 4 (@app (@dot Hand1 toNat) handB))) 3)
       (type:name-subtype 'Nat (type:name 'Int)))
      ((@app randomUInt256) (type:name-subtype 'Nat (type:name 'Int)))
      ((@app winner handA0 handB0) (type:name 'Outcome0))
      ((@app (@dot Hand1 input) "First player, pick your hand") (type:name 'Hand0))
      ((@app (@dot Hand1 input) "Second player, pick your hand") (type:name 'Hand0))
      ((@app (@dot Hand1 toNat) handA) (type:name-subtype 'Nat (type:name 'Int)))
      ((@app (@dot Hand1 toNat) handB) (type:name-subtype 'Nat (type:name 'Int)))
      ((@app (@dot Outcome1 ofNat)
             (@app mod (@app + (@app (@dot Hand1 toNat) handA) (@app - 4 (@app (@dot Hand1 toNat) handB))) 3))
       (type:name 'Outcome0))
      ((@dot Hand1 input) (type:arrow (@list (type:name 'Bytes)) (type:name 'Hand0)))
      ((@dot Hand1 toNat) (type:arrow (@list (type:name 'Hand0)) (type:name-subtype 'Nat (type:name 'Int))))
      ((@dot Outcome1 ofNat) (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Outcome0)))
      ((@make-interaction
        ((@record (participants (@list A B)) (assets (@list DefaultToken))))
        (wagerAmount)
        (@debug-label dlb4)
        (@ A (def handA0 (@app (@dot Hand1 input) "First player, pick your hand")))
        (@debug-label dlb5)
        (@ A (def salt (@app randomUInt256)))
        (@debug-label dlb6)
        (@ A (def commitment (digest (@tuple salt handA0))))
        (@debug-label dlb7)
        (publish! A commitment)
        (@debug-label dlb8)
        (deposit! A (@record (DefaultToken wagerAmount)))
        (@debug-label dlb9)
        (@ B (def handB0 (@app (@dot Hand1 input) "Second player, pick your hand")))
        (@debug-label dlb10)
        (publish! B handB0)
        (@debug-label dlb11)
        (deposit! B (@record (DefaultToken wagerAmount)))
        (@debug-label dlb12)
        (publish! A salt)
        (publish! A handA0)
        (@debug-label dlb13)
        (require! (== commitment (digest (@tuple salt handA0))))
        (@debug-label dlb14)
        (def outcome (@app winner handA0 handB0))
        (@debug-label dlb15)
        (switch outcome
                ((@app-ctor A_Wins) (@debug-label dlb16)
                                    (withdraw! A (@record (DefaultToken (@app * 2 wagerAmount)))))
                ((@app-ctor B_Wins) (@debug-label dlb17)
                                    (withdraw! B (@record (DefaultToken (@app * 2 wagerAmount)))))
                ((@app-ctor Draw) (@debug-label dlb18)
                                  (withdraw! A (@record (DefaultToken wagerAmount)))
                                  (@debug-label dlb19)
                                  (withdraw! B (@record (DefaultToken wagerAmount)))))
        (@debug-label dlb20)
        outcome)
       (type:arrow (@list (type:name 'Participant) (type:name 'Participant) (type:name 'Int)) (type:name 'Outcome0)))
      ((@record (input (λ (tag) (def x (input Hand tag)) x))
                (toNat (λ (x0) (switch x0 ((@app-ctor Rock) 0) ((@app-ctor Paper) 1) ((@app-ctor Scissors) 2))))
                (ofNat (λ (x1) (switch x1 (0 Rock) (1 Paper) (2 Scissors)))))
       (type:record
        (symdict ('toNat (type:arrow (@list (type:name 'Hand0)) (type:name-subtype 'Nat (type:name 'Int))))
                 ('ofNat (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Hand0)))
                 ('input (type:arrow (@list (type:name 'Bytes)) (type:name 'Hand0))))))
      ((@record (input (λ (tag0) (def x2 (input Outcome tag0)) x2))
                (toNat (λ (x3) (switch x3 ((@app-ctor B_Wins) 0) ((@app-ctor Draw) 1) ((@app-ctor A_Wins) 2))))
                (ofNat (λ (x4) (switch x4 (0 B_Wins) (1 Draw) (2 A_Wins)))))
       (type:record
        (symdict ('toNat (type:arrow (@list (type:name 'Outcome0)) (type:name-subtype 'Nat (type:name 'Int))))
                 ('ofNat (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Outcome0)))
                 ('input (type:arrow (@list (type:name 'Bytes)) (type:name 'Outcome0))))))
      ((@tuple salt handA0) (type:tuple (@list (type:name-subtype 'Nat (type:name 'Int)) (type:name 'Hand0))))
      ((deposit! A (@record (DefaultToken wagerAmount))) (type:tuple (@list)))
      ((deposit! B (@record (DefaultToken wagerAmount))) (type:tuple (@list)))
      ((digest (@tuple salt handA0)) (type:name 'Digest))
      ((input Hand tag) (type:name 'Hand0))
      ((input Outcome tag0) (type:name 'Outcome0))
      ((require! (== commitment (digest (@tuple salt handA0)))) (type:tuple (@list)))
      ((switch outcome
               ((@app-ctor A_Wins) (@debug-label dlb16)
                                   (withdraw! A (@record (DefaultToken (@app * 2 wagerAmount)))))
               ((@app-ctor B_Wins) (@debug-label dlb17)
                                   (withdraw! B (@record (DefaultToken (@app * 2 wagerAmount)))))
               ((@app-ctor Draw) (@debug-label dlb18)
                                 (withdraw! A (@record (DefaultToken wagerAmount)))
                                 (@debug-label dlb19)
                                 (withdraw! B (@record (DefaultToken wagerAmount)))))
       (type:tuple (@list)))
      ((switch x0 ((@app-ctor Rock) 0) ((@app-ctor Paper) 1) ((@app-ctor Scissors) 2)) (type:name-subtype 'Nat (type:name 'Int)))
      ((switch x1 (0 Rock) (1 Paper) (2 Scissors)) (type:name 'Hand0))
      ((switch x3 ((@app-ctor B_Wins) 0) ((@app-ctor Draw) 1) ((@app-ctor A_Wins) 2)) (type:name-subtype 'Nat (type:name 'Int)))
      ((switch x4 (0 B_Wins) (1 Draw) (2 A_Wins)) (type:name 'Outcome0))
      ((withdraw! A (@record (DefaultToken wagerAmount))) (type:tuple (@list)))
      ((withdraw! A (@record (DefaultToken (@app * 2 wagerAmount)))) (type:tuple (@list)))
      ((withdraw! B (@record (DefaultToken wagerAmount))) (type:tuple (@list)))
      ((withdraw! B (@record (DefaultToken (@app * 2 wagerAmount)))) (type:tuple (@list)))
      ((λ (handA handB)
          (@debug-label dlb2)
          (@app (@dot Outcome1 ofNat)
                (@app mod (@app + (@app (@dot Hand1 toNat) handA) (@app - 4 (@app (@dot Hand1 toNat) handB))) 3)))
       (type:arrow (@list (type:name 'Hand0) (type:name 'Hand0)) (type:name 'Outcome0)))
      ((λ (tag) (def x (input Hand tag)) x) (type:arrow (@list (type:name 'Bytes)) (type:name 'Hand0)))
      ((λ (tag0) (def x2 (input Outcome tag0)) x2) (type:arrow (@list (type:name 'Bytes)) (type:name 'Outcome0)))
      ((λ (x0) (switch x0 ((@app-ctor Rock) 0) ((@app-ctor Paper) 1) ((@app-ctor Scissors) 2)))
       (type:arrow (@list (type:name 'Hand0)) (type:name-subtype 'Nat (type:name 'Int))))
      ((λ (x1) (switch x1 (0 Rock) (1 Paper) (2 Scissors)))
       (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Hand0)))
      ((λ (x3) (switch x3 ((@app-ctor B_Wins) 0) ((@app-ctor Draw) 1) ((@app-ctor A_Wins) 2)))
       (type:arrow (@list (type:name 'Outcome0)) (type:name-subtype 'Nat (type:name 'Int))))
      ((λ (x4) (switch x4 (0 B_Wins) (1 Draw) (2 A_Wins)))
       (type:arrow (@list (type:name-subtype 'Nat (type:name 'Int))) (type:name 'Outcome0))))
