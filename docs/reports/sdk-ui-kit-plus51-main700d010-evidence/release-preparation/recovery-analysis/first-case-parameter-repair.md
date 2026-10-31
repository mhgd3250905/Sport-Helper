# First-case retry is parameter repair, not duration recovery

Model source `7548ee00955f3811fb9c18139503bb7f04abc11a`, SDK `700d0100f1cb42ef122e774a6ee0076d1916b5e5`.

`5m-01` used six real LLM calls. Response 3 requested `draft_plan` and received
`missing_parameters`, with `actual=["goal"]`. Response 4 supplied `goal` through
`set_params`. Response 5 successfully drafted the plan; response 6 delivered it
with `show_plan`. There were two requested and two executed drafts in total,
but zero `duration_fit_failed` triggers and zero duration-recovery redrafts.
The SDK usage issue-code record independently contains only `missing_parameters`.

The failed draft key is `5m-01:response-3:tool-call_00_iGyRl7yjlNKPoxLenI3S1134`. Full receipt JSON pointers and all
subsequent tools are retained in `case-5m-01.json`; `verification.json` provides
the independent call/usage/token reconciliation.

All five cases delivered a plan without a structured question, and all five
passed the current scheduled-duration acceptance policy. The first case's
287 seconds include one self-paced `h-kneeling-pushup` phase: 10 repetitions,
30 estimated seconds. It is explicitly an estimate and does not fail this
round's acceptance; automatic natural completion is not asserted for that phase.
The other cases have no self-paced phases and retain their natural-clock proof.

All five new duration failures, blocked asks, duration redraft requests/executions
and other infeasible counts are zero. These samples therefore do not exercise
the SDK duration-recovery branch. There were 24 successful logical LLM calls
and 24 SDK-reported HTTP attempts, no real requests were repeated by analysis.
Input/output/total tokens are 254462/8058/262520. Cached tokens are already in
input and reasoning tokens already in output; neither is added again. Reasoning
token coverage is incomplete (21 observed calls, 3 unknown, known subtotal4324),
so its full aggregate remains null rather than zero or an estimate.

All seven captured case/summary/binding file hashes remain unchanged.
