(hash (Buyer (type:name 'Participant))
      (Seller (type:name 'Participant))
      (digest0 (type:name 'Digest))
      (isValidSignature (type:arrow (@list (type:name 'Participant) (type:name 'Digest) (type:name 'Signature)) (type:name 'Bool)))
      (buySig
       (type:arrow (@list (type:name 'Participant) (type:name 'Participant) (type:name 'Digest) (type:name-subtype 'Nat (type:name 'Int))) (type:tuple (@list))))
      (price (type:name-subtype 'Nat (type:name 'Int)))
      (signature (type:name 'Signature))
      ((@app isValidSignature Seller digest0 signature) (type:name 'Bool))
      ((@make-interaction
        ((@record (participants (@list Buyer Seller)) (assets (@list DefaultToken))))
        (digest0 price)
        (@debug-label dlb0)
        (deposit! Buyer (@record (DefaultToken price)))
        (@debug-label dlb1)
        (@ Seller (def signature (sign digest0)))
        (publish! Seller signature)
        (require! (@app isValidSignature Seller digest0 signature))
        (@debug-label dlb2)
        (withdraw! Seller (@record (DefaultToken price))))
       (type:arrow (@list (type:name 'Participant) (type:name 'Participant) (type:name 'Digest) (type:name-subtype 'Nat (type:name 'Int))) (type:tuple (@list))))
      ((deposit! Buyer (@record (DefaultToken price))) (type:tuple (@list)))
      ((require! (@app isValidSignature Seller digest0 signature)) (type:tuple (@list)))
      ((sign digest0) (type:name 'Signature))
      ((withdraw! Seller (@record (DefaultToken price))) (type:tuple (@list))))
