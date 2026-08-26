# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-08-26T11:17:40.396068Z","feature_name":"Filler Word Control","feature_path":"features/filler_word_control.feature","background_hash":"151a63a15af270e9d7b0dafe5376b29f80e482c8414fb0236be330f9be34738f","implementation_hash":"sha256:3ad96575663e30f416bca8094f290071d75caef054895808ea217ba4858d7fc8","scenarios":[{"index":0,"name":"Filler Word Control 01","scenario_hash":"155494e2416143b132bf6ee0caaaeafc52927bb37248452875190764b0361f64","mutation_count":4,"result":{"Total":4,"Killed":4,"Survived":0,"Errors":0},"tested_at":"2026-08-26T10:55:21.933119Z"}]}
# acceptance-mutation-manifest-end

Feature: Filler Word Control

Background:
  Given the app is running

# Filler Word Control 01
Scenario: Filler Word Control 01
  When I open the <settings_tab> settings tab
  Then the tab shows the control <expected_control>

  Examples:
    | settings_tab | expected_control           |
    | Vocabulary   | remove filler words toggle |
    | Vocabulary   | filler word list           |

# Filler Word Control 02
Scenario: Filler Word Control 02
  Given filler word removal is turned <removal_state>
  And the dictated audio contains the word <filler_word>
  When the transcript is delivered
  Then the transcript <filler_outcome> the word <filler_word>

  Examples:
    | removal_state | filler_outcome | filler_word |
    | on            | omits          | um          |
    | off           | keeps          | um          |

# Filler Word Control 03
Scenario: Filler Word Control 03
  Given filler word removal is turned <removal_state>
  And the dictated audio contains the word <filler_word>
  And I remove <filler_word> from the filler word list
  When the transcript is delivered
  Then the transcript <filler_outcome> the word <filler_word>

  Examples:
    | removal_state | filler_outcome | filler_word |
    | on            | keeps          | um          |
    | on            | keeps          | basically   |
