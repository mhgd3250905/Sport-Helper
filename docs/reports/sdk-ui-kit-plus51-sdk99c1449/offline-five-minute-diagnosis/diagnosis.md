# SDK99 five-minute clarification: offline diagnosis

The original real call remains unchanged. This diagnostic replays its three captured tools-only response batches with FakeLlmClient, the exact original user text, the App production catalogue/profile and regenerated unique tool IDs. It performs zero real model requests, consumes zero new model tokens, disables application HTTP clients and does not answer the clarification.

The replay reproduces the same question. The actual draft_plan receipt is ok=true/status=infeasible/needsUserChoice=true, with reason=minimum_exceeds_target, target=300s, tolerance=10%, minEstimatedSec=336 and maxEstimatedSec=14044. No plan version was delivered. The bounds-only receipt has no fitLog, and the turn has no PlanIssue errors; it is a handled clarification, not a successful plan.

## Minimum arithmetic

| Selected action | Smallest legal catalogue/profile dose | Seconds |
| --- | --- | ---: |
| h-chair-sit-to-stand | Fixed 3 sets x 12 reps x default 3s/rep + 2 x 30s rest | 168 |
| h-squat | 1 set x 6 reps x 4s/rep | 24 |
| h-incline-pushup | 1 set x 5 reps x 4s/rep | 20 |
| h-good-morning | 1 set x 6 reps x 4s/rep | 24 |
| h-doorframe-forearms-pec-native-r3 | Fixed 1 set x 30 seconds | 30 |
| Preparation | SF default | 10 |
| Four transitions | 4 x 15 seconds | 60 |
| Total | Minimum one round per block | 336 |

336 exceeds the 330s acceptance ceiling. The independent per-block maximum also matches 14044s.

The chair catalogue fixes sets=[3,3], reps=[12,12], restSeconds=[30,30]. Those are catalogue constraints, not user dose locks. The pre-draft ledger has scene/minutes/goal/level/equipment and default limits, but no dose parameter. All five IDs come from the recorded model draft.

The chair is self_paced: its 3s/rep is the Coach fallback estimate, not a guaranteed automatic execution duration. The bound proves this selected combination cannot fit the planning budget. It does not prove every five-minute selection is impossible or establish physical-device timing.

## Owning SDK99 code

All source pointers refer to commit 99c14495685f160019e10340ea6f0de6418a65b9, not the SDK worktree's current slots branch.

- lib/src/agent/plan_builder.dart:411-453 intersects catalogue/profile ranges and initializes doses; 591-615 checks bounds before _fit.
- lib/src/agent/plan_timing.dart:477-520 evaluates monotone legal extremes and classifies minimum > target*1.1 as minimum_exceeds_target.
- lib/src/agent/draft_tool_handler.dart:107-118 returns feasibility without a plan version.
- lib/src/agent/coach_agent.dart:2382-2417 converts status=infeasible to a clarification and pauses without another model attempt. This branch does not require a user dose lock or user-confirmed selected IDs.

This is a selected-combination lower-bound rejection, not duration_fit_failed from a bounded search miss, a user-imposed fixed dose, a transport failure, or proof of an SDK defect. Whether an unfixed model-selected combination should first return to action selection is a product/control-flow decision; this diagnostic changes no rule, dose, target or selection.

## Evidence boundaries

The original real LLM timings/tokens remain exclusively in ../live-durations-99c1449/plan-5-minutes.json. This offline run is causal evidence, not another live generation attempt.

- offline-replay.json: actual replay draft receipt, final ledger, original tool arguments and selected definitions.
- tool-receipts.json and history.json: public protocol receipts/history.
- requests-and-pre-call-states.json: exact pre-draft source ledger.
- independent-bound-ledger.json: per-item/per-block minimum and maximum arithmetic.
- formal-profile.json and replayed-tool-calls.json: unchanged configuration and recorded order.
- offline-replay-test-r1.log preserves the helper's initial compile error; r2.log records the successful single offline test after correcting HttpOverrides.current.
