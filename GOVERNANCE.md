# Governance

The project uses maintainer review with recorded technical decisions. Correctness changes require one systems review and one economics-domain review. A maintainer may merge routine documentation and CI repairs; public API, accounting, determinism, market-matching, and validation changes require two approvals. Releases require a green support matrix, an immutable tag, a signed-off validation report, and no open correctness defect.

Maintainers disclose conflicts, document rejected alternatives in design records, and may revert a change immediately when it violates a conservation, replay, temporal, or accounting invariant. Governance is intended to expand to elected maintainers after two independent contributors have shipped validated model work.
