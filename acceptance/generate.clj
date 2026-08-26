#!/usr/bin/env bb
;; Acceptance entrypoint generator (adapter shell).
;;
;; Reads the APS intermediate representation produced by `gherkin-parser` and
;; writes the executable XCTest source, plus the per-feature metadata that
;; `gherkin-mutator` reads. All of the IR-to-Swift mapping lives in
;; `acceptance.generator` and the metadata shape in `acceptance.metadata`, both
;; pure and spec'd; this file only does argument handling, hashing, and file IO.
;;
;; usage: generate.clj <out.swift> <features-dir> <ir.json>...

(ns generate
  (:require [acceptance.generator :as generator]
            [acceptance.metadata :as metadata]
            [babashka.fs :as fs]
            [cheshire.core :as json])
  (:import [java.security MessageDigest]))

(defn- read-ir [f]
  (let [ir (json/parse-string (slurp f) true)]
    (when-not (generator/feature-ir? ir)
      (throw (ex-info (str "not an APS feature IR: " f) {:file f})))
    ir))

(defn- sha256 [text]
  (->> (.digest (MessageDigest/getInstance "SHA-256") (.getBytes text "UTF-8"))
       (map #(format "%02x" %))
       (apply str)))

(defn- feature-path
  "The feature file an IR came from. gherkin-parser writes <stem>.json for
  <features-dir>/<stem>.feature, so the stem carries the pairing."
  [features-dir ir-file]
  (str (fs/path features-dir (str (fs/strip-ext (fs/file-name ir-file)) ".feature"))))

(defn- write-metadata! [out features-dir ir-files generated-hash]
  (let [dir (fs/path (fs/parent out) "metadata")
        ;; bin/acceptance passes absolute paths; the metadata is committed, so
        ;; record them relative to the repo this ran in.
        repo-root (System/getProperty "user.dir")]
    (fs/create-dirs dir)
    (doseq [ir-file ir-files]
      (let [feature (feature-path features-dir ir-file)]
        (spit (str (fs/path dir (metadata/metadata-name feature)))
              (json/generate-string
               (metadata/metadata {:repo-root repo-root
                                   :feature-path feature
                                   :ir-path ir-file
                                   :generated-files [out]
                                   :implementation-hash generated-hash})
               {:pretty true}))))))

(defn -main [& args]
  (let [[out features-dir & ir-files] args
        ir-files (sort ir-files)]
    (when (or (nil? out) (nil? features-dir) (empty? ir-files))
      (println "usage: generate.clj <out.swift> <features-dir> <ir.json>...")
      (System/exit 2))
    (fs/create-dirs (fs/parent out))
    (let [source (generator/source (map read-ir ir-files))]
      (spit out source)
      (write-metadata! out features-dir ir-files (sha256 source)))
    (println "GENERATED" out)))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
