#!/usr/bin/env bb
;; Acceptance manifest builder (adapter shell).
;;
;; Collects the project facts and runtime measurements the generated acceptance
;; tests assert against, and writes them to one JSON file. Keeping the probing
;; here means the generated tests stay pure assertions over a snapshot, and a
;; fact that cannot be gathered (no build artifact, app not launchable in this
;; environment) is recorded as null so the scenario reports a skip with a
;; reason instead of a false pass.
;;
;; This file runs the probes; `acceptance.facts` owns reading their output.

(ns manifest
  (:require [acceptance.facts :as facts]
            [babashka.fs :as fs]
            [babashka.process :refer [shell]]
            [cheshire.core :as json]))

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

(defn deployment-target []
  ;; -derivedDataPath keeps the probe's cache inside the worktree; without it
  ;; xcodebuild seeds ~/Library/Developer/Xcode/DerivedData on every run.
  (facts/deployment-target
   (sh-out "xcodebuild" "-project" (path "Sotto.xcodeproj")
           "-scheme" "Sotto"
           "-derivedDataPath" (path ".local-build-test")
           "-showBuildSettings")))

(defn documented-minimum-macos []
  (->> ["README.md" "BUILDING.md"]
       (map #(path %))
       (filter fs/exists?)
       (map slurp)
       facts/documented-versions))

(defn declared-swift-types []
  (->> (fs/glob (path "Sotto") "**/*.swift")
       (map #(slurp (str %)))
       facts/all-declared-types))

(defn resolved-packages []
  (let [f (path "Sotto.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")]
    (when (fs/exists? f)
      (facts/package-identities (json/parse-string (slurp f) true)))))

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

(defn bundle-resources [app]
  (when app
    (facts/unique-sorted (map fs/file-name (fs/glob app "**")))))

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
    (facts/symbol-lines (map #(sh-out "nm" "-U" %) (mach-o-binaries app)))))

(defn bundle-size-mb [app]
  (when app
    (facts/du-megabytes (sh-out "du" "-sm" app))))

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
