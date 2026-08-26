# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-08-26T12:05:18.509002Z","feature_name":"Mac Platform Conformance","feature_path":"features/mac_platform_conformance.feature","background_hash":"9a747fa73d5caf245f49179124c484af9e3344264d3e6ceb71f7d7b77714eda2","implementation_hash":"sha256:d55a66dd75b364fefe4822c3c0d097c27cf9f31038d2741bf647d015b063e8e7","scenarios":[{"index":0,"name":"Mac Platform Conformance 01","scenario_hash":"bcf57d490590a94d756596fff4fbb0be650a54f79a086a5ee23b3a79ffd296f0","mutation_count":1,"result":{"Total":1,"Killed":1,"Survived":0,"Errors":0},"tested_at":"2026-08-26T10:57:15.851041Z"},{"index":2,"name":"Mac Platform Conformance 03","scenario_hash":"9e32604be1b9f6ddca6cbc749256c367339549e96961aa8d508abde8734bc075","mutation_count":4,"result":{"Total":4,"Killed":4,"Survived":0,"Errors":0},"tested_at":"2026-08-26T10:57:15.851041Z"}]}
# acceptance-mutation-manifest-end

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
