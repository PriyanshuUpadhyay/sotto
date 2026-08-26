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
