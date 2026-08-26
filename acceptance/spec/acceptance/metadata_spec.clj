(ns acceptance.metadata-spec
  (:require [acceptance.metadata :as sut]
            [speclj.core :refer :all]))

(describe "metadata-name"
  (it "lowercases the path and hyphenates every separator"
    (should= "features-hunt-the-wumpus-feature.json"
             (sut/metadata-name "features/Hunt The Wumpus.feature")))

  (it "collapses a run of non-alphanumeric characters into one hyphen"
    (should= "features-api-v2-happy-path-feature.json"
             (sut/metadata-name "Features/API v2/Happy Path.feature")))

  (it "keeps nested directories distinct"
    (should= "features-orders-cancel-order-feature.json"
             (sut/metadata-name "features/orders/Cancel Order.feature")))

  (it "trims leading and trailing hyphens"
    (should= "a-feature.json" (sut/metadata-name "/a.feature/"))))

(describe "metadata"
  (with built (sut/metadata {:feature-path "features/a.feature"
                             :ir-path "tmp/acceptance/ir/a.json"
                             :generated-files ["SottoTests/Generated/GeneratedAcceptanceTests.swift"]
                             :implementation-hash "abc123"}))

  (it "records the feature path, which the mutator checks before trusting the hash"
    (should= "features/a.feature" (:feature_path @built)))

  (it "records the IR the generation read"
    (should= "tmp/acceptance/ir/a.json" (:ir_path @built)))

  (it "prefixes the implementation hash with its algorithm"
    (should= "sha256:abc123" (:implementation_hash @built)))

  (it "declares that the hash covers only the generated files"
    (should= "generated_files" (:hash_scope @built))
    (should= ["SottoTests/Generated/GeneratedAcceptanceTests.swift"] (:generated_files @built)))

  (it "carries the schema version"
    (should= 1 (:schema_version @built))))
