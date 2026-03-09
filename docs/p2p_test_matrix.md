# P2P NAT Test Matrix

## Scope

- Make P2P strategy regression repeatable in CI.
- Compare rollback profile (`P0`) and new strategy profiles (`P1/P2/P3`).
- Output machine-readable baseline metrics.

## NAT Scenarios

| Scenario | Local NAT | Peer NAT |
|---|---|---|
| S1 | Cone | Cone |
| S2 | Cone | EasySym |
| S3 | EasySym | EasySym |
| S4 | HardSym | Cone |
| S5 | HardSym | HardSym |

## Feature Profiles

| Profile | p2p-orchestrator-v2 | p2p-nat-profile-v2 | p2p-easysym-v1 | p2p-path-memory-v1 |
|---|---|---|---|---|
| P0 | N | N | N | N |
| P1 | Y | Y | Y | Y |
| P2 | Y | Y | N | Y |
| P3 | Y | N | N | Y |

## Execution

1. Choose scenario `Sx` and profile `Px`.
2. Run fixed rounds (recommended `N=200`).
3. Collect `event.p2p.*` logs.
4. Run parser script:

```bash
bash docs/p2p_matrix_baseline.sh <log_file> <scenario_id> [output_jsonl]
```

## Metrics

- `direct_success_rate`
- `relay_commit_rate`
- `connect_fail_rate`
- `first_connect_p95_ms`
- `path_memory_hit_rate`
- `circuit_breaker_arm_rate`
- `relay_reason_distribution`

## CI Mapping

- PR: run core deterministic unit tests + parser script validation.
- Schedule: run the same key set daily.
