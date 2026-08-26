(ns acceptance.metadata
  "Builds the per-feature generator metadata that `gherkin-mutator` reads.

  The mutator looks for `<generated-dir>/metadata/<name>.json` and trusts its
  `implementation_hash` only when `feature_path` matches the feature it was
  asked to mutate, so both fields are derived here rather than guessed.

  Pure: `acceptance/generate.clj` owns hashing the file and writing the JSON."
  (:require [clojure.string :as str]))

(defn metadata-name
  "The metadata filename APS derives from a feature path: lowercased, every run
  of non-alphanumeric characters collapsed to one hyphen, ends trimmed."
  [feature-path]
  (-> feature-path
      str/lower-case
      (str/replace #"[^a-z0-9]+" "-")
      (str/replace #"^-+|-+$" "")
      (str ".json")))

(defn metadata
  "The metadata object for one feature. `implementation-hash` covers only the
  generated files, which is the scope APS specifies."
  [{:keys [feature-path ir-path generated-files implementation-hash]}]
  {:schema_version 1
   :feature_path feature-path
   :ir_path ir-path
   :implementation_hash (str "sha256:" implementation-hash)
   :hash_scope "generated_files"
   :generated_files (vec generated-files)})

;; clj-mutate-manifest-begin
;; {:version 1, :tested-at "2026-08-26T16:56:14.016367+05:30", :module-hash "-2101357853", :forms [{:id "form/0/ns", :kind "ns", :line 1, :end-line nil, :hash "461422444"} {:id "defn/metadata-name", :kind "defn", :line 11, :end-line nil, :hash "-786815352"} {:id "defn/metadata", :kind "defn", :line 21, :end-line nil, :hash "-1171193581"}]}
;; clj-mutate-manifest-end
