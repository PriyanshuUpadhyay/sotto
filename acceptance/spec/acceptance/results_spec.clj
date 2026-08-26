(ns acceptance.results-spec
  (:require [acceptance.results :as sut]
            [speclj.core :refer :all]))

(defn- case-node [name result & failures]
  {:nodeType "Test Case"
   :name name
   :result result
   :children (map (fn [f] {:nodeType "Failure Message" :name f}) failures)})

(def tree
  [{:nodeType "Test Plan"
    :name "Sotto"
    :children [{:nodeType "Unit test bundle"
                :name "SottoTests"
                :children [(case-node "test_A_row1()" "Passed")
                           (case-node "test_B_row1()" "Failed" "expected 26.0; got 15.0")
                           (case-node "test_C_row1()" "Skipped")]}]}])

(describe "nodes"
  (it "walks the node and its descendants"
    (should= ["root" "child" "grandchild"]
             (map :name (sut/nodes {:name "root"
                                    :children [{:name "child"
                                                :children [{:name "grandchild"}]}]}))))

  (it "returns just the node when it has no children"
    (should= ["leaf"] (map :name (sut/nodes {:name "leaf"})))))

(describe "test-cases"
  (it "finds the cases nested under the bundles"
    (should= ["test_A_row1()" "test_B_row1()" "test_C_row1()"]
             (map :name (sut/test-cases tree))))

  (it "ignores nodes that are not test cases"
    (should= [] (sut/test-cases [{:nodeType "Test Plan" :name "Sotto"}]))))

(describe "failure-text"
  (it "joins every failure message of the case"
    (should= "first\nsecond"
             (sut/failure-text (case-node "test_X()" "Failed" "first" "second"))))

  (it "is empty for a case that did not fail"
    (should= "" (sut/failure-text (case-node "test_X()" "Passed")))))

(describe "summary"
  (it "counts the passes"
    (should= 1 (:passed (sut/summary tree))))

  (it "keeps the failed cases, because the report spells out why"
    (should= ["test_B_row1()"] (map :name (:failed (sut/summary tree)))))

  (it "keeps the skipped cases, because a skip is not a pass"
    (should= ["test_C_row1()"] (map :name (:skipped (sut/summary tree)))))

  (it "reports zeros for an empty run"
    (should= {:passed 0 :failed [] :skipped []} (sut/summary []))))

(describe "report-lines"
  (it "leads with a blank line and the heading"
    (should= ["" "==> acceptance results"]
             (take 2 (sut/report-lines (sut/summary [])))))

  (it "reports the three counts"
    (should= ["    passed  1" "    failed  1" "    skipped 1"]
             (->> (sut/report-lines (sut/summary tree)) (drop 2) (take 3))))

  (it "names each skipped scenario without a reason, which the skip text carries"
    (should-contain "  test_C_row1()" (sut/report-lines (sut/summary tree))))

  (it "prints only the name of a skipped scenario, never its recorded reason"
    (should= ["" "--- skipped ---" "  test_S_row1()"]
             (->> (sut/report-lines
                    (sut/summary [(case-node "test_S_row1()" "Skipped" "needs a live app process")]))
                  (drop 5))))

  (it "spells out why each failed scenario failed"
    (should-contain "    expected 26.0; got 15.0" (sut/report-lines (sut/summary tree))))

  (it "omits both sections when everything passed"
    (should= 5 (count (sut/report-lines (sut/summary [{:nodeType "Test Case"
                                                      :name "test_A()"
                                                      :result "Passed"}]))))))
