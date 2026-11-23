# Agent instructions

## Finish the work

Do not leave a task partially done, and do not defer anything you are able to
complete in the same turn.

- Finish the stated task, then finish the verification that belongs to it. If a
  build, test or check is the natural proof that the change works, run it
  before reporting the result.
- Do not stop at "this should work" when a check exists that would show whether
  it does.
- Do not offer remaining work as a follow-up suggestion when you could have done
  it yourself. Suggestions are for genuinely separate, optional next steps, not
  for the rest of the current task.
- If something truly blocks completion (missing credentials, a device you cannot
  reach, an unapproved production action), say plainly what is unfinished, why,
  and what the user must do — never present it as finished or quietly drop it.
- A task is finished when the change is made, the relevant checks have run, and
  any leftover state (background processes, temporary files, backups) has been
  cleaned up.
