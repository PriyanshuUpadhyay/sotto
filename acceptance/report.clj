#!/usr/bin/env bb
;; Acceptance reporter (adapter shell).
;;
;; xcodebuild prints only pass/fail lines for a parallel run and keeps the
;; assertion text in the result bundle, so a failing scenario would otherwise
;; say nothing about WHY. This reads the bundle and prints one line per
;; scenario row, with the failing step and reason spelled out.
;;
;; The counting and formatting live in `acceptance.results`; this file only
;; runs `xcresulttool` and prints.

(ns report
  (:require [acceptance.results :as results]
            [babashka.process :refer [shell]]
            [cheshire.core :as json]))

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
    (let [summary (results/summary (:testNodes (json/parse-string out true)))]
      (doseq [line (results/report-lines summary)]
        (println line))
      (flush)
      (System/exit (if (seq (:failed summary)) 1 0)))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
