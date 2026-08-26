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

;; clj-mutate-manifest-begin
;; {:version 1, :tested-at "2026-08-26T16:55:36.64075+05:30", :module-hash "1775052732", :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line nil, :hash "979531120"} {:id "def/declaration-pattern", :kind "def", :line 8, :end-line nil, :hash "-1666871127"} {:id "def/documented-version-pattern", :kind "def", :line 11, :end-line nil, :hash "59953182"} {:id "def/deployment-target-pattern", :kind "def", :line 13, :end-line nil, :hash "165220735"} {:id "defn/unique-sorted", :kind "defn", :line 15, :end-line nil, :hash "-1532597783"} {:id "defn/deployment-target", :kind "defn", :line 20, :end-line nil, :hash "-2009531154"} {:id "defn/documented-version", :kind "defn", :line 29, :end-line nil, :hash "-1785629369"} {:id "defn/documented-versions", :kind "defn", :line 34, :end-line nil, :hash "1189007296"} {:id "defn/declared-types", :kind "defn", :line 40, :end-line nil, :hash "479690181"} {:id "defn/all-declared-types", :kind "defn", :line 46, :end-line nil, :hash "-1221188373"} {:id "defn/package-identities", :kind "defn", :line 51, :end-line nil, :hash "1694554549"} {:id "defn/symbol-lines", :kind "defn", :line 56, :end-line nil, :hash "-95094818"} {:id "defn/du-megabytes", :kind "defn", :line 62, :end-line nil, :hash "542036481"}]}
;; clj-mutate-manifest-end
