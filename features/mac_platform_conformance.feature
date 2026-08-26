Feature: Mac Platform Conformance

Background:
  Given a release build of Sotto

# Mac Platform Conformance 01
Scenario: Mac Platform Conformance 01
  When I read the documented minimum macOS version
  Then it equals the build setting MACOSX_DEPLOYMENT_TARGET
  And it equals <supported_version>

  Examples:
    | supported_version |
    | 26.0              |

# Mac Platform Conformance 02
Scenario: Mac Platform Conformance 02
  Given the host runs macOS <installed_version>
  When I launch the app
  Then the launch result is <launch_outcome>

  Examples:
    | installed_version | launch_outcome                      |
    | 26.0              | opens its menu bar item             |
    | 15.0              | reports an unsupported macOS version |

# Mac Platform Conformance 03
Scenario: Mac Platform Conformance 03
  Given VoiceOver is running
  And the app is running
  When I move VoiceOver focus to the control <control_name>
  Then VoiceOver announces a non-empty label for that control

  Examples:
    | control_name          |
    | menu bar item         |
    | dictionary add button |
    | review undo button    |
    | review copy button    |

# Mac Platform Conformance 04
Scenario: Mac Platform Conformance 04
  Given the system appearance is <system_appearance>
  And the app appearance preference is <appearance_preference>
  When I open the Sotto window
  Then the window renders in <rendered_appearance>

  Examples:
    | system_appearance | appearance_preference | rendered_appearance |
    | dark              | follow system         | dark                |
    | light             | follow system         | light               |
    | dark              | light                 | light               |
    | light             | dark                  | dark                |
