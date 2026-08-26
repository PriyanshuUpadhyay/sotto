# acceptance-mutation-manifest-begin
# {"version":1,"tested_at":"2026-08-26T12:11:34.136921Z","feature_name":"Pipeline Latency","feature_path":"features/pipeline_latency.feature","background_hash":"61edff38a817d89f1cc2bdada7acb8a53a97f125c4c16f644a0a737e9f3d3fca","implementation_hash":"sha256:d55a66dd75b364fefe4822c3c0d097c27cf9f31038d2741bf647d015b063e8e7","scenarios":[{"index":8,"name":"Pipeline Latency 09","scenario_hash":"34620294c01b41effc33aac356c8c4f90ea677b061e7d6e41d68e8a02d217574","mutation_count":4,"result":{"Total":4,"Killed":4,"Survived":0,"Errors":0},"tested_at":"2026-08-26T12:11:34.136921Z"}]}
# acceptance-mutation-manifest-end

Feature: Pipeline Latency

Background:
  Given a release build of Sotto on Apple Silicon
  And a warm transcription model

# Pipeline Latency 01
Scenario: Pipeline Latency 01
  When an utterance finishes the pipeline
  Then the pipeline trace reports a duration for the stage <stage_name>

  Examples:
    | stage_name       |
    | asr              |
    | boosting         |
    | filter           |
    | wordReplacement  |
    | acoustic         |
    | phonetic         |
    | enhancement      |

# Pipeline Latency 02
Scenario: Pipeline Latency 02
  When the app enhances a transcript of <transcript_chars> characters
  Then the instruction prompt holds at most <prompt_budget_chars> characters

  Examples:
    | transcript_chars | prompt_budget_chars |
    | 136              | 5200                |
    | 1540             | 5200                |

# Pipeline Latency 03
Scenario: Pipeline Latency 03
  Given the enhancement session is warm
  When the app enhances <sample_count> transcripts
  Then the metric <metric_name> at <percentile> is at most <budget_ms> milliseconds

  Examples:
    | sample_count | metric_name      | percentile | budget_ms |
    | 100          | timeToFirstToken | p50        | 500       |
    | 100          | timeToFirstToken | p90        | 750       |
    | 100          | totalGeneration  | p50        | 800       |
    | 100          | totalGeneration  | p90        | 1400      |
    | 100          | preparation      | p90        | 50        |

# Pipeline Latency 04
Scenario: Pipeline Latency 04
  When the app enhances <sample_count> transcripts
  Then at least <reuse_budget_percent> percent reuse a warm session

  Examples:
    | sample_count | reuse_budget_percent |
    | 100          | 95                   |

# Pipeline Latency 05
Scenario: Pipeline Latency 05
  When I stop a recording of <record_seconds> seconds
  Then the review editor appears within <preview_budget_ms> milliseconds at <percentile>

  Examples:
    | record_seconds | percentile | preview_budget_ms |
    | 10             | p50        | 300               |
    | 10             | p90        | 800               |

# Pipeline Latency 06
Scenario: Pipeline Latency 06
  When I record <record_seconds> seconds of speech with the <engine_name> engine
  Then the asr stage real time factor is at most <rtf_budget>

  Examples:
    | engine_name | record_seconds | rtf_budget |
    | Parakeet    | 10             | 0.10       |
    | Parakeet    | 30             | 0.10       |
    | Whisper     | 10             | 0.30       |
    | Whisper     | 30             | 0.30       |

# Pipeline Latency 07
Scenario: Pipeline Latency 07
  When an utterance finishes the pipeline
  Then the stage <stage_name> adds at most <stage_budget_ms> milliseconds

  Examples:
    | stage_name      | stage_budget_ms |
    | boosting        | 60              |
    | filter          | 10              |
    | wordReplacement | 10              |
    | acoustic        | 60              |
    | phonetic        | 30              |

# Pipeline Latency 08
Scenario: Pipeline Latency 08
  Given the dictated audio contains the word <spoken_token>
  When the transcript reaches the enhancement stage
  Then the enhancement input <token_outcome> the word <spoken_token>

  Examples:
    | spoken_token | token_outcome |
    | um           | omits         |
    | uh           | omits         |

# Pipeline Latency 09
Scenario: Pipeline Latency 09
  Given the transcript <cleanliness> already correct punctuation
  When the transcript reaches the enhancement stage
  Then the model call <call_outcome>

  Examples:
    | cleanliness | call_outcome |
    | has         | happens      |
    | lacks       | happens      |
