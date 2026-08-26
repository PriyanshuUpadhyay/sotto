# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-08-26T12:14:29.582960Z","feature_name":"Unreachable Code Removal","feature_path":"features/unreachable_code.feature","background_hash":"9a747fa73d5caf245f49179124c484af9e3344264d3e6ceb71f7d7b77714eda2","implementation_hash":"sha256:d55a66dd75b364fefe4822c3c0d097c27cf9f31038d2741bf647d015b063e8e7","scenarios":[{"index":4,"name":"Unreachable Code Removal 05","scenario_hash":"40685d4d577105b3dfce80354438da07fd02adbd2950047e4ad3299762b3a73b","mutation_count":6,"result":{"Total":6,"Killed":6,"Survived":0,"Errors":0},"tested_at":"2026-08-26T11:23:39.469396Z"}]}
# acceptance-mutation-manifest-end

Feature: Unreachable Code Removal

Background:
  Given a release build of Sotto

# Unreachable Code Removal 01
Scenario: Unreachable Code Removal 01
  When the build completes
  Then no Swift source file declares the type <unreachable_type>
  And the shipped binary exports no symbol for <unreachable_type>

  Examples:
    | unreachable_type         |
    | TacticalGlass            |
    | SottoGeometry            |
    | VisualEffectView         |
    | AppIconView              |
    | SaveIconButton           |
    | GlassChip                |
    | GlassSwitch              |
    | SlidingPanel             |
    | HistoryShortcutTipView   |
    | ReasoningConfig          |
    | AudioDeviceConfiguration |
    | DictionarySettingsView   |
    | SectionCard              |

# Unreachable Code Removal 02
Scenario: Unreachable Code Removal 02
  When the build completes
  Then the app bundle contains no resource named <absent_resource>

  Examples:
    | absent_resource            |
    | mlx-swift_Cmlx.bundle      |
    | swift-transformers_Hub.bundle |
    | swift-crypto_Crypto.bundle |

# Unreachable Code Removal 03
Scenario: Unreachable Code Removal 03
  When the build completes
  Then the build resolves no package dependency named <absent_dependency>

  Examples:
    | absent_dependency  |
    | mlx-swift          |
    | mlx-swift-lm       |
    | swift-transformers |
    | swift-huggingface  |

# Unreachable Code Removal 04
Scenario: Unreachable Code Removal 04
  When I enable the hidden preference <hidden_flag>
  And I enhance a transcript
  Then the enhancement runs on the <expected_provider> provider

  Examples:
    | hidden_flag           | expected_provider |
    | EnhancementProviderMLX | AppleFoundation  |

# Unreachable Code Removal 05
Scenario: Unreachable Code Removal 05
  Given the app is running
  When I open the <settings_tab> settings tab
  Then the tab shows the control <expected_control>

  Examples:
    | settings_tab | expected_control     |
    | Vocabulary   | dictionary word list |
    | Vocabulary   | word replacement list |
    | General      | device priority list  |
