# SDK700d010 real-sample offline recovery audit

App source: `7548ee00955f3811fb9c18139503bb7f04abc11a`; SDK: `700d0100f1cb42ef122e774a6ee0076d1916b5e5`.
This is offline analysis of previously captured real requests. No new model call, automatic answer, device operation, SDK or App change occurred.

| case | scheduled seconds incl. prep | self-paced phases | automatic-clock evidence | new duration failures | executed/requested redrafts | blocked asks | other infeasible | structured question delivered | exact counts | >20s / >8 calls |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| 5m-01 | 287.0 | 1 | False | 0 | 0/0 | 0 | 0 | False | True | False / False |
| 5m-02 | 317.0 | 0 | True | 0 | 0/0 | 0 | 0 | False | True | False / False |
| 5m-03 | 309.0 | 0 | True | 0 | 0/0 | 0 | 0 | False | True | False / False |
| 10m-01 | 629.0 | 0 | True | 0 | 0/0 | 0 | 0 | False | True | False / False |
| 20m-01 | 1242.0 | 0 | True | 0 | 0/0 | 0 | 0 | False | True | False / False |

Counts are keyed by case, original LLM response occurrence and SDK-normalized tool ID. Repeated history is never another execution. `duration_fit_failed` from `ask_user` is a blocked attempt, separated from a new fitting/selection failure. A requested draft is not executed when its receipt is skipped or deferred.

Redraft requests count `draft_plan` calls emitted in later model responses while the preceding duration recovery is pending. Same-batch calls already emitted before the failure are listed separately and do not become a model retry. Executed redrafts require an observed non-skip receipt, or the explicit successful-terminal-prefix proof.

Successful terminal evidence uses the delivered plan plus the last accepted usage record with no issue codes. SDK700d010 skips every call after a batch failure and stops after output, so the preceding successful final-batch prefix can be classified without inventing a receipt. Error/cancelled endings retain null exact counts if the required final receipts are unavailable.

`sdkTurnResult.question`, accepted-clarification flags, actual chat question objects, accepted `askUser` events and asked/awaitingUser receipts are checked independently. Raw assistant text remains available for human review; keywords or punctuation never establish a tool execution or a delivered structured question.

All strong plan/independence/no-clarification checks passed: **True**.
All five plans delivered without structured clarification, with scheduled/card totals in tolerance: **True**.
All automatic execution evidence established: **False**. Unproven cases: `['5m-01']`.
All recovery counts exact: **True**.
No duration recovery was triggered in these five real samples. These samples do not demonstrate a real model repairing a duration failure; SDK recovery tests and any offline replay remain separate evidence.
Per the current user instruction, self-paced work is labeled estimated and does not fail plan-duration acceptance. Automatic-clock evidence is separately reported and remains unproven for such phases.
Performance anomaly flags are separate from duration correctness and do not change the selected samples.

## 5m-01

Full ledger and JSON pointers: `case-5m-01.json`.

The delivered plan and scheduled/card total are within the requested tolerance, but self_paced work requires manual completion. Its phase.seconds is an estimate, not a proven timed/automatic execution duration. Per the current explicit user instruction this estimate is accepted and is not an acceptance failure; automatic natural completion is still not claimed.

```json
[
  {
    "workPhaseIndex": 2,
    "jsonPointer": "/workPhases/2",
    "phase": {
      "id": "h-kneeling-pushup",
      "seconds": 30.0,
      "set": 1,
      "sets": 1,
      "round": 0,
      "rounds": 0,
      "side": null,
      "selfPaced": true,
      "reps": 10,
      "repSeconds": null,
      "rhythm": {
        "kind": "self_paced"
      }
    }
  }
]
```

## 5m-02

Full ledger and JSON pointers: `case-5m-02.json`.

## 5m-03

Full ledger and JSON pointers: `case-5m-03.json`.

## 10m-01

Full ledger and JSON pointers: `case-10m-01.json`.

## 20m-01

Full ledger and JSON pointers: `case-20m-01.json`.
