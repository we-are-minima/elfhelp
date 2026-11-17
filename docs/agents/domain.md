# Domain Docs

This project uses a single context: `GLOSSARY.md` at the repository root and architecture decision records in `docs/adr/`.

## Before exploring the codebase

Read `GLOSSARY.md` and the ADRs in `docs/adr/` relevant to the area being explored.

If these files do not exist, proceed silently. The `domain-modeling` skill creates them when terms or decisions are resolved.

## Use the glossary's vocabulary

When naming a domain concept in an issue, proposal, test, or other output, use the term defined in `GLOSSARY.md`.

If a concept is missing, reconsider whether it belongs to the project's vocabulary; note genuine gaps for `domain-modeling`.

## Flag ADR conflicts

If a proposal contradicts an existing ADR, identify that decision and explain why it should be reconsidered.
