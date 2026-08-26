# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-08-26T12:12:36.524229Z","feature_name":"Runtime Budgets","feature_path":"features/runtime_budgets.feature","background_hash":"d36dae0ec65c955c3469ee55024654b48fe19c0f38e1006bc7ba43b61f80577f","implementation_hash":"sha256:d55a66dd75b364fefe4822c3c0d097c27cf9f31038d2741bf647d015b063e8e7","scenarios":[]}
# acceptance-mutation-manifest-end

Feature: Runtime Budgets

Background:
  Given a release build of Sotto on Apple Silicon
  And no transcription model download is in progress

# Runtime Budgets 01
Scenario: Runtime Budgets 01
  Given the app is not running
  When I launch the app
  Then the menu bar item responds within <launch_budget_ms> milliseconds

  Examples:
    | launch_budget_ms |
    | 1500             |

# Runtime Budgets 02
Scenario: Runtime Budgets 02
  Given the app is running
  And no recording is active
  When I sample the process for <sample_seconds> seconds
  Then average CPU stays below <cpu_budget_percent> percent
  And idle resident memory stays below <memory_budget_mb> megabytes

  Examples:
    | sample_seconds | cpu_budget_percent | memory_budget_mb |
    | 60             | 1                  | 400              |

# Runtime Budgets 03
Scenario: Runtime Budgets 03
  Given the app is running
  When I record for <record_seconds> seconds with the <engine_name> engine
  Then peak resident memory stays below <memory_budget_mb> megabytes

  Examples:
    | engine_name | record_seconds | memory_budget_mb |
    | Parakeet    | 30             | 1400             |
    | Whisper     | 30             | 1200             |

# Runtime Budgets 04
Scenario: Runtime Budgets 04
  Given the app is running
  When a recording ends and the transcript is delivered
  Then resident memory returns below <idle_budget_mb> megabytes within <settle_seconds> seconds

  Examples:
    | idle_budget_mb | settle_seconds |
    | 400            | 30             |

# Runtime Budgets 05
Scenario: Runtime Budgets 05
  When the build completes
  Then the installed app bundle is smaller than <bundle_budget_mb> megabytes

  Examples:
    | bundle_budget_mb |
    | 60               |
