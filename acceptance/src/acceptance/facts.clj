(ns acceptance.facts
  "Extracts the acceptance manifest's facts out of the text the probes collect.

  Pure: `acceptance/manifest.clj` owns running the probes and touching the
  filesystem, so every parsing rule the scenarios depend on is spec'd here."
  (:require [clojure.string :as str]))

(def ^:private declaration-pattern
  #"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)")

(def ^:private documented-version-pattern #"(?i)macOS\s+(\d+(?:\.\d+)?)\s+or later")

(def ^:private deployment-target-pattern #"MACOSX_DEPLOYMENT_TARGET\s*=\s*(\S+)")

(defn unique-sorted
  "The distinct values, sorted, as a vector."
  [values]
  (->> values distinct sort vec))

(defn deployment-target
  "MACOSX_DEPLOYMENT_TARGET as it appears in `xcodebuild -showBuildSettings`
  output, or nil when the probe produced nothing."
  [build-settings]
  (some->> build-settings
           str/split-lines
           (keep #(second (re-find deployment-target-pattern %)))
           first))

(defn documented-version
  "The macOS version a doc promises, or nil when it promises none."
  [doc-text]
  (second (re-find documented-version-pattern doc-text)))

(defn documented-versions
  "Every distinct minimum macOS version the given docs promise. More than one
  means the docs disagree, which is what the scenario asserts against."
  [doc-texts]
  (->> doc-texts (keep documented-version) distinct vec))

(defn declared-types
  "Every type name declared in one Swift source."
  [swift-source]
  (->> (str/split-lines swift-source)
       (keep #(second (re-find declaration-pattern %)))))

(defn all-declared-types
  "Every type name declared across the given Swift sources."
  [swift-sources]
  (unique-sorted (mapcat declared-types swift-sources)))

(defn package-identities
  "The package identities a parsed `Package.resolved` pins."
  [resolved]
  (->> resolved :pins (map :identity) sort vec))

(defn symbol-lines
  "The symbol names the `nm` runs reported, one per line. A run that produced
  nothing contributes nothing."
  [nm-outputs]
  (->> nm-outputs (mapcat #(some-> % str/split-lines)) vec))

(defn du-megabytes
  "The size in MB from `du -sm` output, or nil when the probe produced nothing."
  [du-output]
  (some-> du-output (str/split #"\s+") first parse-long))
