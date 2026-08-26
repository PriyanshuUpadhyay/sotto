(ns acceptance.properties-spec
  "Property specs for the acceptance pipeline's pure namespaces.

  These live outside `spec/` so coverage, CRAP, and mutation see only the
  example-based specs. Run them with the explicit `make acceptance-property`
  command."
  (:require [acceptance.facts :as facts]
            [acceptance.generator :as generator]
            [acceptance.results :as results]
            [clojure.string :as str]
            [clojure.test.check :as tc]
            [clojure.test.check.generators :as gen]
            [clojure.test.check.properties :as prop]
            [speclj.core :refer :all]))

(def ^:private trials 200)

(defn- holds
  "Checks `property`, and on failure reports the shrunk counterexample and the
  seed that reproduces it."
  [property]
  (let [{:keys [pass? seed shrunk] :as result} (tc/quick-check trials property)]
    (when-not pass?
      (-fail (str "property failed after " (:num-tests result) " trials"
                  "\n  seed:           " seed
                  "\n  counterexample: " (pr-str (:smallest shrunk)))))
    true))

(def ^:private gen-step-text
  (gen/fmap #(str/join " " %) (gen/vector gen/string-alphanumeric 0 6)))

(def ^:private gen-example
  (gen/map (gen/elements [:tab :control :word :budget])
           gen/string-alphanumeric
           {:max-elements 4}))

(def ^:private gen-scenario
  (gen/hash-map :name gen/string-alphanumeric
                :steps (gen/vector (gen/hash-map :text gen-step-text) 0 4)
                :examples (gen/vector gen-example 0 4)))

(describe "generator/identifier"
  (it "emits only Swift-safe characters, never at the edges (invariant)"
    (should (holds (prop/for-all [text gen/string]
                     (let [id (generator/identifier text)]
                       (and (re-matches #"[A-Za-z0-9_]*" id)
                            (not (str/starts-with? id "_"))
                            (not (str/ends-with? id "_"))))))))

  (it "is idempotent, so a name that survived once survives again"
    (should (holds (prop/for-all [text gen/string]
                     (let [id (generator/identifier text)]
                       (= id (generator/identifier id))))))))

(describe "generator/swift-string"
  (it "round trips: unescaping the literal gives the original text back"
    (should (holds (prop/for-all [text gen/string]
                     (let [literal (generator/swift-string text)
                           body (subs literal 1 (dec (count literal)))]
                       (= text (str/replace body #"\\(.)" "$1"))))))))

(describe "generator/rows"
  (it "emits one row per example, or exactly one when there are none (conservation)"
    (should (holds (prop/for-all [scenario gen-scenario]
                     (= (max 1 (count (:examples scenario)))
                        (count (generator/rows scenario)))))))

  (it "numbers the rows 1..n in order (ordering)"
    (should (holds (prop/for-all [scenario gen-scenario]
                     (let [indexes (map :index (generator/rows scenario))]
                       (= indexes (range 1 (inc (count indexes)))))))))

  (it "addresses each row by its zero-based position in the IR (invariant)"
    (should (holds (prop/for-all [scenario gen-scenario]
                     (every? #(= (:example-index %) (dec (:index %)))
                             (generator/rows scenario)))))))

(describe "facts/unique-sorted"
  (it "is sorted, duplicate free, and keeps the same set (invariant)"
    (should (holds (prop/for-all [values (gen/vector gen/string-alphanumeric 0 20)]
                     (let [result (facts/unique-sorted values)]
                       (and (= result (sort result))
                            (= (count result) (count (distinct result)))
                            (= (set values) (set result))))))))

  (it "is idempotent"
    (should (holds (prop/for-all [values (gen/vector gen/string-alphanumeric 0 20)]
                     (let [once (facts/unique-sorted values)]
                       (= once (facts/unique-sorted once))))))))

(describe "facts/du-megabytes"
  (it "round trips any size du could report"
    (should (holds (prop/for-all [size gen/nat
                                  path (gen/not-empty gen/string-alphanumeric)]
                     (= size (facts/du-megabytes (str size "\t/" path "\n"))))))))

(describe "facts/symbol-lines"
  (it "keeps every line of every readable binary and drops the unreadable ones (conservation)"
    (should (holds (prop/for-all [outputs (gen/vector
                                           (gen/one-of
                                            [(gen/return nil)
                                             (gen/fmap #(str/join "\n" %)
                                                       (gen/not-empty
                                                        (gen/vector (gen/not-empty gen/string-alphanumeric) 1 5)))])
                                           0 5)]
                     (= (reduce + (map #(count (str/split-lines %)) (remove nil? outputs)))
                        (count (facts/symbol-lines outputs))))))))

(describe "results/summary"
  (it "accounts for every test case exactly once (conservation)"
    (should (holds (prop/for-all [cases (gen/vector
                                         (gen/hash-map
                                          :nodeType (gen/return "Test Case")
                                          :name gen/string-alphanumeric
                                          :result (gen/elements ["Passed" "Failed" "Skipped"]))
                                         0 20)]
                     (let [{:keys [passed failed skipped]} (results/summary cases)]
                       (= (count cases) (+ passed (count failed) (count skipped)))))))))

(describe "results/report-lines"
  (it "always leads with the heading and the three counts (invariant)"
    (should (holds (prop/for-all [cases (gen/vector
                                         (gen/hash-map
                                          :nodeType (gen/return "Test Case")
                                          :name (gen/not-empty gen/string-alphanumeric)
                                          :result (gen/elements ["Passed" "Failed" "Skipped"]))
                                         0 10)]
                     (let [summary (results/summary cases)
                           lines (vec (results/report-lines summary))]
                       (and (= "" (lines 0))
                            (= "==> acceptance results" (lines 1))
                            (= (str "    passed  " (:passed summary)) (lines 2))
                            (= (str "    failed  " (count (:failed summary))) (lines 3))
                            (= (str "    skipped " (count (:skipped summary))) (lines 4)))))))))
