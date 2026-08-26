(ns acceptance.results
  "Reads an xcresult test-node tree into the per-scenario acceptance summary.

  Pure: the shell owns running `xcresulttool` and printing, so the counting and
  the failure text assembly are spec'd directly against node trees."
  (:require [clojure.string :as str]))

(defn nodes
  "The node and every descendant, depth first."
  [node]
  (cons node (mapcat nodes (:children node))))

(defn test-cases
  "Every \"Test Case\" node under `roots`."
  [roots]
  (filter #(= "Test Case" (:nodeType %)) (mapcat nodes roots)))

(defn failure-text
  "The failure messages of one test case, one per line."
  [case-node]
  (->> (nodes case-node)
       (filter #(= "Failure Message" (:nodeType %)))
       (map :name)
       (str/join "\n")))

(defn summary
  "Counts and the failed/skipped cases of one result bundle's test nodes."
  [test-nodes]
  (let [by-result (group-by :result (test-cases test-nodes))]
    {:passed (count (get by-result "Passed"))
     :failed (vec (get by-result "Failed"))
     :skipped (vec (get by-result "Skipped"))}))

(defn- case-lines [{:keys [name] :as case-node} detailed?]
  (cons (str "  " name)
        (when detailed?
          (map #(str "    " %) (str/split-lines (failure-text case-node))))))

(defn- section-lines [title cases detailed?]
  (when (seq cases)
    (concat ["" (str "--- " title " ---")]
            (mapcat #(case-lines % detailed?) cases))))

(defn report-lines
  "The report exactly as the shell prints it, one string per line."
  [{:keys [passed failed skipped]}]
  (concat ["" "==> acceptance results"
           (format "    passed  %d" passed)
           (format "    failed  %d" (count failed))
           (format "    skipped %d" (count skipped))]
          (section-lines "skipped" skipped false)
          (section-lines "failed" failed true)))
