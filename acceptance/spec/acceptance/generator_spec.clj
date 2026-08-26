(ns acceptance.generator-spec
  (:require [acceptance.generator :as sut]
            [clojure.string :as str]
            [speclj.core :refer :all]))

(def one-step-scenario
  {:name "Filler Word Control 01"
   :steps [{:text "I open the <settings_tab> settings tab"}]
   :examples [{:settings_tab "Vocabulary"}]})

(describe "substitute"
  (it "replaces a placeholder with its example value"
    (should= "I open the Vocabulary settings tab"
             (sut/substitute "I open the <settings_tab> settings tab"
                             {:settings_tab "Vocabulary"})))

  (it "replaces every occurrence of the same placeholder"
    (should= "um then um"
             (sut/substitute "<w> then <w>" {:w "um"})))

  (it "replaces each placeholder in turn"
    (should= "Vocabulary shows filler word list"
             (sut/substitute "<tab> shows <control>"
                             {:tab "Vocabulary" :control "filler word list"})))

  (it "renders a non-string value as its printed form"
    (should= "under 1500 ms" (sut/substitute "under <budget> ms" {:budget 1500})))

  (it "leaves text alone when the example is empty"
    (should= "the app is running" (sut/substitute "the app is running" {}))))

(describe "swift-string"
  (it "quotes plain text"
    (should= "\"the app is running\"" (sut/swift-string "the app is running")))

  (it "escapes embedded quotes"
    (should= "\"say \\\"um\\\"\"" (sut/swift-string "say \"um\"")))

  (it "escapes backslashes before quotes, so an escape is not double-escaped"
    (should= "\"a\\\\b\"" (sut/swift-string "a\\b"))))

(describe "identifier"
  (it "keeps letters and digits"
    (should= "Filler01" (sut/identifier "Filler01")))

  (it "collapses each run of other characters into one underscore"
    (should= "Filler_Word_Control_01" (sut/identifier "Filler Word Control 01")))

  (it "trims leading and trailing underscores"
    (should= "Runtime_Budgets" (sut/identifier " Runtime  Budgets! "))))

(describe "rows"
  (it "numbers the rows from one"
    (should= [1 2] (map :index (sut/rows {:steps [] :examples [{} {}]}))))

  (it "substitutes each row's values into every step"
    (should= [["I open the Vocabulary settings tab"]]
             (map :steps (sut/rows one-step-scenario))))

  (it "runs a scenario with no examples once, unsubstituted"
    (should= [{:index 1 :steps ["the app is running"]}]
             (map #(update % :steps vec)
                  (sut/rows {:name "X" :steps [{:text "the app is running"}]}))))

  (it "runs a scenario with an empty examples table once"
    (should= 1 (count (sut/rows {:name "X" :steps [] :examples []})))))

(describe "method"
  (with generated (sut/method {:name "Filler Word Control"}
                              one-step-scenario
                              (first (sut/rows one-step-scenario))))

  (it "names the method after the scenario and row"
    (should-contain "func test_Filler_Word_Control_01_row1() throws {" @generated))

  (it "passes the feature and scenario names through"
    (should-contain "feature: \"Filler Word Control\"" @generated)
    (should-contain "scenario: \"Filler Word Control 01\"" @generated))

  (it "passes the substituted steps as Swift strings"
    (should-contain "\"I open the Vocabulary settings tab\"" @generated))

  (it "carries no assertion of its own"
    (should-not-contain "XCTAssert" @generated)))

(describe "class-source"
  (with feature {:name "Filler Word Control"
                 :scenarios [one-step-scenario
                             (assoc one-step-scenario :name "Filler Word Control 02")]})

  (it "names the class after the feature"
    (should-contain "final class Filler_Word_ControlAcceptanceTests: XCTestCase {"
                    (sut/class-source @feature)))

  (it "emits one method per scenario example row"
    (should= 2 (count (re-seq #"func test_" (sut/class-source @feature)))))

  (it "runs on the main actor, because the steps touch view state"
    (should (str/starts-with? (sut/class-source @feature) "@MainActor\n"))))

(describe "feature-ir?"
  (it "accepts an IR that names the feature and carries scenarios"
    (should (sut/feature-ir? {:name "F" :scenarios []})))

  (it "rejects an IR with no name"
    (should-not (sut/feature-ir? {:scenarios []})))

  (it "rejects an IR with no scenarios"
    (should-not (sut/feature-ir? {:name "F"}))))

(describe "source"
  (with generated (sut/source [{:name "Filler Word Control"
                                :scenarios [one-step-scenario]}]))

  (it "warns that the file is generated"
    (should-contain "Do not edit by hand" @generated))

  (it "imports XCTest and the app under test"
    (should-contain "import XCTest\n@testable import Sotto\n" @generated))

  (it "emits one class per feature"
    (should= 2 (count (re-seq #"final class "
                              (sut/source [{:name "A" :scenarios []}
                                           {:name "B" :scenarios []}]))))))
