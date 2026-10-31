# Captured SmartFit five-minute v3

The adjacent JSON is copied byte-for-byte from SDK main
`caa6817c51b3cb09c46909288d83aa88bdc2dbd4`,
`packages/ugk_trainer/test/fixtures/smartfit/five-minute/plan-v3.json`.
SHA-256: `67d833cd2fdbdb9559cf13428f2ca27bfccfc1b7d6e4ec927c333fc8ccbeb994`.

The SDK fixture manifest binds it to the real third model turn captured in
SmartFit `94e924fe287770f56d4e8ceeedd521e2871267da`. It retains the inherited
diagnostic seed summary and original doses; it is not a new generated plan.

The host regression verifies the original 313-second Coach estimate and the
345-second execution including preparation. The aligned catalogue estimates
344 seconds; the preserved squat's one-off lead contributes the remaining
second, and the card uses the complete 345-second schedule. The unchanged
historical dose remains outside five minutes +10%. Fresh model plans have a
separate gate; this fixture is never rewritten to make that gate pass.
