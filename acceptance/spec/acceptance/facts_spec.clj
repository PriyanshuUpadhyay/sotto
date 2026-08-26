(ns acceptance.facts-spec
  (:require [acceptance.facts :as sut]
            [speclj.core :refer :all]))

(describe "unique-sorted"
  (it "drops duplicates and sorts"
    (should= ["a" "b" "c"] (sut/unique-sorted ["c" "a" "b" "a"])))

  (it "returns an empty vector for no values"
    (should= [] (sut/unique-sorted []))))

(describe "deployment-target"
  (it "reads the setting out of xcodebuild output"
    (should= "26.0" (sut/deployment-target "    SDKROOT = macosx26.0\n    MACOSX_DEPLOYMENT_TARGET = 26.0\n")))

  (it "takes the first value when a multi-target build reports several"
    (should= "26.0" (sut/deployment-target "MACOSX_DEPLOYMENT_TARGET = 26.0\nMACOSX_DEPLOYMENT_TARGET = 15.0")))

  (it "is nil when the setting is absent, so the scenario skips"
    (should-be-nil (sut/deployment-target "SDKROOT = macosx26.0")))

  (it "is nil when the probe produced nothing"
    (should-be-nil (sut/deployment-target nil))))

(describe "documented-version"
  (it "reads the promised minimum"
    (should= "26.0" (sut/documented-version "- macOS 26.0 or later")))

  (it "reads a major-only promise"
    (should= "26" (sut/documented-version "Requires macOS 26 or later.")))

  (it "ignores case, because the docs are prose"
    (should= "26.0" (sut/documented-version "requires MacOS 26.0 or later")))

  (it "is nil when the doc promises nothing"
    (should-be-nil (sut/documented-version "# Building Sotto"))))

(describe "documented-versions"
  (it "reports one version when the docs agree"
    (should= ["26.0"] (sut/documented-versions ["macOS 26.0 or later"
                                                "needs macOS 26.0 or later"])))

  (it "reports both when the docs disagree, which is the failure the scenario names"
    (should= ["26.0" "15.0"] (sut/documented-versions ["macOS 26.0 or later"
                                                       "macOS 15.0 or later"])))

  (it "skips docs that promise nothing"
    (should= [] (sut/documented-versions ["# Sotto" ""]))))

(describe "declared-types"
  (it "finds a plain declaration"
    (should= ["ReviewTray"] (sut/declared-types "struct ReviewTray {}")))

  (it "finds every declaration kind"
    (should= ["A" "B" "C" "D" "E" "F"]
             (sut/declared-types (str "struct A {}\nclass B {}\nenum C {}\n"
                                      "actor D {}\nprotocol E {}\ntypealias F = Int"))))

  (it "sees through access and finality modifiers"
    (should= ["GlassChip"] (sut/declared-types "public final class GlassChip: View {}")))

  (it "sees an indented, nested declaration"
    (should= ["Section"] (sut/declared-types "    enum Section: CaseIterable {}")))

  (it "ignores a mention that is not a declaration"
    (should= [] (sut/declared-types "let tray = ReviewTray()\n// struct comment"))))

(describe "all-declared-types"
  (it "merges the sources, dropping duplicates and sorting"
    (should= ["Alpha" "Beta"]
             (sut/all-declared-types ["struct Beta {}" "struct Alpha {}\nstruct Beta {}"]))))

(describe "package-identities"
  (it "lists the pinned identities in sorted order"
    (should= ["axswift" "fluidaudio"]
             (sut/package-identities {:pins [{:identity "fluidaudio"} {:identity "axswift"}]})))

  (it "is empty when nothing is pinned"
    (should= [] (sut/package-identities {:pins []}))))

(describe "symbol-lines"
  (it "splits each nm run into lines"
    (should= ["_a" "_b" "_c"] (sut/symbol-lines ["_a\n_b" "_c"])))

  (it "ignores a run that produced nothing, so one unreadable binary is not fatal"
    (should= ["_a"] (sut/symbol-lines [nil "_a"])))

  (it "is empty when there were no binaries to scan"
    (should= [] (sut/symbol-lines []))))

(describe "du-megabytes"
  (it "reads the size out of du -sm output"
    (should= 42 (sut/du-megabytes "42\t/Applications/Sotto.app\n")))

  (it "is nil when the probe produced nothing, so the budget scenario skips"
    (should-be-nil (sut/du-megabytes nil)))

  (it "is nil when the output is not a number"
    (should-be-nil (sut/du-megabytes "du: no such file"))))
