# Ralph

Ralph runs an autonomous agent through plan, build and review phases, handing work between them through shared artifacts.

## Language

**Review**:
The cycle's gatekeeper: a single pass that decides what must be fixed before the cycle's work counts as done. Repetition comes from cycles, never from re-running review within one.
_Avoid_: Audit, spec-fidelity check

**Finding**:
A falsifiable claim that the tree fails a named standard, filed as a plan item for build to fix.
_Avoid_: Issue, observation, nit

**Cycle**:
One pass of work from plan through the last build, ending when the artifacts are archived.
_Avoid_: Run, iteration

**Cycle base**:
The HEAD of every repository in the workspace, recorded just before build's first commit of the cycle. The cycle's work is everything between the cycle base and HEAD.
_Avoid_: Baseline, start commit

**Standard**:
What a finding measures the tree against: a clause of a cited spec, a written rule, or code quality. All three carry equal weight.
_Avoid_: Criterion, check

**Severity**:
A finding's rank by consequence, whatever its standard. Critical: wrong behaviour under a reachable condition, however latent. Major: a missing safety net. Minor: code that misleads or burdens its reader.
_Avoid_: Priority, level

**Lens**:
One standard's view of the cycle's work, examined separately and merged with the others before anything is filed.
_Avoid_: Slice, subagent, check

**Finding kind**:
One entry in review's closed catalogue of defects and smells, each carrying its own test of proof. A code-quality finding must name its kind and pass that kind's test.
_Avoid_: Category, smell type
