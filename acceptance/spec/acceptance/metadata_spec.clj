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

(describe "repo-relative"
  (it "drops the repo root from an absolute path"
    (should= "features/a.feature" (sut/repo-relative "/w/sotto" "/w/sotto/features/a.feature")))

  (it "leaves a path that is already relative alone"
    (should= "features/a.feature" (sut/repo-relative "/w/sotto" "features/a.feature")))

  (it "leaves a path outside the repo alone, rather than mangling it"
    (should= "/elsewhere/a.feature" (sut/repo-relative "/w/sotto" "/elsewhere/a.feature")))

  (it "does not treat a sibling directory with the same prefix as inside the repo"
    (should= "/w/sotto-other/a.feature" (sut/repo-relative "/w/sotto" "/w/sotto-other/a.feature"))))

(describe "metadata"
  (with built (sut/metadata {:repo-root "/w/sotto"
                             :feature-path "features/a.feature"
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
    (should= 1 (:schema_version @built)))

  (it "records every path relative to the repo root, so the file is machine independent"
    (let [built (sut/metadata {:repo-root "/w/sotto"
                               :feature-path "/w/sotto/features/a.feature"
                               :ir-path "/w/sotto/tmp/acceptance/ir/a.json"
                               :generated-files ["/w/sotto/SottoTests/Generated/GeneratedAcceptanceTests.swift"]
                               :implementation-hash "abc123"})]
      (should= "features/a.feature" (:feature_path built))
      (should= "tmp/acceptance/ir/a.json" (:ir_path built))
      (should= ["SottoTests/Generated/GeneratedAcceptanceTests.swift"] (:generated_files built)))))
