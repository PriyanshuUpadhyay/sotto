#!/usr/bin/env bb
;; Acceptance entrypoint generator (adapter shell).
;;
;; Reads the APS intermediate representation produced by `gherkin-parser` and
;; writes the executable XCTest source. All of the IR-to-Swift mapping lives in
;; `acceptance.generator`, which is pure and spec'd; this file only does the
;; argument handling and file IO that specs cannot run.

(ns generate
  (:require [acceptance.generator :as generator]
            [babashka.fs :as fs]
            [cheshire.core :as json]))

(defn- read-ir [f]
  (let [ir (json/parse-string (slurp f) true)]
    (when-not (generator/feature-ir? ir)
      (throw (ex-info (str "not an APS feature IR: " f) {:file f})))
    ir))

(defn -main [& args]
  (let [out (first args)
        ir-files (sort (rest args))]
    (when (or (nil? out) (empty? ir-files))
      (println "usage: generate.clj <out.swift> <ir.json>...")
      (System/exit 2))
    (fs/create-dirs (fs/parent out))
    (spit out (generator/source (map read-ir ir-files)))
    (println "GENERATED" out)))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
