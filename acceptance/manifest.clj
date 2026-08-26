#!/usr/bin/env bb
;; Acceptance manifest builder.
;;
;; Collects the project facts and runtime measurements the generated acceptance
;; tests assert against, and writes them to one JSON file. Keeping the probing
;; here means the generated tests stay pure assertions over a snapshot, and a
;; fact that cannot be gathered (no build artifact, app not launchable in this
;; environment) is recorded as null so the scenario reports a skip with a
;; reason instead of a false pass.

(ns manifest
  (:require [babashka.fs :as fs]
            [babashka.process :refer [shell]]
            [cheshire.core :as json]
            [clojure.string :as str]))

(def repo-root (str (fs/canonicalize (or (System/getenv "SOTTO_REPO") "."))))

(defn- path [& parts] (str (apply fs/path repo-root parts)))

(defn- sh-out
  "Runs a command and returns stdout, or nil when it fails."
  [& args]
  (try
    (let [{:keys [exit out]} (apply shell {:out :string :err :string :continue true} args)]
      (when (zero? exit) out))
    (catch Exception _ nil)))

;; ---------------------------------------------------------------- build facts

(defn deployment-target
  "MACOSX_DEPLOYMENT_TARGET as xcodebuild resolves it for the Sotto target."
  []
  (some->> (sh-out "xcodebuild" "-project" (path "Sotto.xcodeproj")
                   "-target" "Sotto" "-showBuildSettings")
           str/split-lines
           (keep #(second (re-find #"MACOSX_DEPLOYMENT_TARGET\s*=\s*(\S+)" %)))
           first))

(defn documented-minimum-macos
  "The minimum macOS version the user-facing docs promise."
  []
  (->> ["README.md" "BUILDING.md"]
       (map #(path %))
       (filter fs/exists?)
       (keep (fn [f]
               (some->> (slurp f)
                        (re-find #"(?i)macOS\s+(\d+(?:\.\d+)?)\s+or later")
                        second)))
       distinct
       vec))

(defn declared-swift-types
  "Every type name declared anywhere under Sotto/."
  []
  (->> (fs/glob (path "Sotto") "**/*.swift")
       (mapcat (fn [f]
                 (->> (slurp (str f))
                      str/split-lines
                      (keep #(second (re-find #"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)" %))))))
       distinct
       sort
       vec))

(defn resolved-packages
  "Package identities SwiftPM actually resolved for this project."
  []
  (let [f (path "Sotto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")]
    (when (fs/exists? f)
      (->> (json/parse-string (slurp f) true) :pins (map :identity) sort vec))))

;; --------------------------------------------------------------- app artifact

(defn app-bundle
  "Path to the built app. `SOTTO_ACCEPTANCE_APP` wins so `bin/acceptance` can
  point the probes at the Release build the features actually talk about."
  []
  (->> [(System/getenv "SOTTO_ACCEPTANCE_APP")
        (path ".local-build-acceptance/Build/Products/Release/Sotto.app")
        (path ".local-build/Build/Products/Debug/Sotto.app")
        (path ".local-build-test/Build/Products/Debug/Sotto.app")
        "/Applications/Sotto.app"]
       (filter some?)
       (filter fs/exists?)
       first))

(defn bundle-resources
  "Every resource file name inside the app bundle."
  [app]
  (when app
    (->> (fs/glob app "**")
         (map #(fs/file-name %))
         distinct
         sort
         vec)))

(defn- mach-o-binaries
  "The app's own executable plus any Sotto dylib beside it. A debug build ships
  a stub executable and puts the real code in Sotto.debug.dylib, so scanning
  only Contents/MacOS/Sotto would report an empty symbol table."
  [app]
  (->> (concat [(fs/path app "Contents/MacOS/Sotto")]
               (fs/glob (str (fs/path app "Contents")) "**/Sotto*.dylib"))
       (map str)
       (filter fs/exists?)))

(defn binary-symbols
  "Symbol names the shipped binaries define. Swift manglings embed the type
  name literally, so a substring search over this list answers \"does the binary
  still carry this type\"."
  [app]
  (when app
    (->> (mach-o-binaries app)
         (mapcat (fn [bin] (some-> (sh-out "nm" "-U" bin) str/split-lines)))
         vec)))

(defn bundle-size-mb [app]
  (when app
    (some-> (sh-out "du" "-sm" app)
            (str/split #"\s+")
            first
            parse-long)))

;; ------------------------------------------------------------------- assembly

(defn build []
  (let [app (app-bundle)]
    {:repoRoot repo-root
     :deploymentTarget (deployment-target)
     :documentedMinimumMacOS (documented-minimum-macos)
     :declaredSwiftTypes (declared-swift-types)
     :resolvedPackages (resolved-packages)
     :appBundlePath app
     :bundleResources (bundle-resources app)
     :binarySymbols (binary-symbols app)
     :appBundleSizeMB (bundle-size-mb app)}))

(defn -main [& [out]]
  (let [out (or out (path "tmp/acceptance/manifest.json"))]
    (fs/create-dirs (fs/parent out))
    (spit out (json/generate-string (build) {:pretty true}))
    (println "MANIFEST" out)))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
