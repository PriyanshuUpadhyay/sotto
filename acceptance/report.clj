#!/usr/bin/env bb
;; Acceptance reporter.
;;
;; xcodebuild prints only pass/fail lines for a parallel run and keeps the
;; assertion text in the result bundle, so a failing scenario would otherwise
;; say nothing about WHY. This reads the bundle and prints one line per
;; scenario row, with the failing step and reason spelled out.

(ns report
  (:require [babashka.process :refer [shell]]
            [cheshire.core :as json]
            [clojure.string :as str]))

(defn- nodes [node]
  (cons node (mapcat nodes (:children node))))

(defn- test-cases [root]
  (filter #(= "Test Case" (:nodeType %)) (nodes root)))

(defn- failure-text [case-node]
  (->> (nodes case-node)
       (filter #(= "Failure Message" (:nodeType %)))
       (map :name)
       (str/join "\n")))

(defn -main [& [bundle]]
  (when-not bundle
    (println "usage: report.clj <path.xcresult>")
    (System/exit 2))
  (let [{:keys [exit out]} (shell {:out :string :err :string :continue true}
                                  "xcrun" "xcresulttool" "get" "test-results" "tests"
                                  "--path" bundle "--compact")]
    (when-not (zero? exit)
      (println "could not read" bundle)
      (System/exit 1))
    (let [cases (mapcat test-cases (:testNodes (json/parse-string out true)))
          by-result (group-by :result cases)
          failed (get by-result "Failed")
          skipped (get by-result "Skipped")]
      (println)
      (println "==> acceptance results")
      (printf "    passed  %d%n" (count (get by-result "Passed")))
      (printf "    failed  %d%n" (count failed))
      (printf "    skipped %d%n" (count skipped))
      (when (seq skipped)
        (println)
        (println "--- skipped ---")
        (doseq [c skipped] (printf "  %s%n" (:name c))))
      (when (seq failed)
        (println)
        (println "--- failed ---")
        (doseq [c failed]
          (printf "  %s%n" (:name c))
          (doseq [line (str/split-lines (failure-text c))]
            (printf "    %s%n" line))))
      (flush)
      (System/exit (if (seq failed) 1 0)))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
