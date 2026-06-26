---
name: prd-to-dt-plan
description: "Translate PRD-style requirement files into a structured implementation plan for a target Snowflake Dynamic Table. Use when: onboarding new sources, adding fields, or applying business rules to Silver-layer DTs. Triggers: prd, requirements to plan, onboard source, dynamic table plan."
---

# PRD to Dynamic Table Plan

Convert product/business requirement documents (XLSX, CSV) into a concrete, reviewable implementation plan for a target Snowflake Dynamic Table.

## When to Use

- A stakeholder hands you a PRD, requirements spreadsheet, or onboarding tracker
- You need to translate business rules into Silver-layer DT changes
- You want a structured gap analysis before writing SQL

## Inputs

| Parameter | Required | Description |
|-----------|----------|-------------|
| `prd_path` | Yes | Path to the requirements file (XLSX or CSV). May be multiple files. |
| `target_dynamic_table` | Yes | Fully-qualified name of the target DT (e.g., `SILVER_AP_INVOICES`) |
| `existing_dt_sql` | No | Path to current DT definition SQL for gap analysis |

## Workflow

### Step 1: Parse Requirements

**Actions:**

1. Read the file(s) at `prd_path`.
   - For XLSX: use the Read tool (supports `.xlsx` natively). Identify sheets — look for tabs like "Source Onboarding", "Business Rules", "Field Mapping", "Open Items".
   - For CSV: read directly.
2. Classify each row into one of these categories:
   - **Source Onboarding** — new source system to integrate
   - **Field Mapping** — new or changed column
   - **Business Rule** — transformation, normalization, dedup, or filter logic
   - **Data Quality** — threshold, alert, or DMF requirement
   - **Out of Scope** — explicitly deferred to Gold, Phase 2, etc.

3. If `existing_dt_sql` is provided, read it and extract the current column list and source systems.

**STOP**: Present the parsed summary to the user. Confirm nothing was misclassified before proceeding.

### Step 2: Identify Changes to Target DT

**Actions:**

For each requirement, determine impact on `target_dynamic_table`:

1. **New sources** — list each with:
   - Source system name and platform
   - Delivery mechanism (CDC, batch, connector)
   - Refresh cadence
   - Bronze table name (known or proposed)

2. **New or modified columns** — for each:
   - Column name (Silver standard)
   - Source mapping per system
   - Data type
   - Nullable?
   - Default/fallback value

3. **Transformation rules** — for each:
   - Rule ID and description
   - SQL pattern (CASE, QUALIFY, COALESCE, etc.)
   - Which UNION ALL branch(es) it affects
   - Whether it is a Silver concern or deferred to Gold

4. **Dropped/ignored columns** — columns explicitly excluded at Silver boundary

**STOP**: Present the change matrix. Get approval before generating the plan.

### Step 3: Surface Assumptions and Open Questions

**CRITICAL: Never guess. Always surface.**

For each ambiguity, produce a structured entry:

```
| # | Question | Why It Matters | Suggested Default | Owner |
```

Common ambiguity patterns to check:
- Normalization layer unclear (Silver vs Gold)
- Format changes over time (old vs new codes in same source)
- Legal/compliance blockers (DPAs, data sharing agreements)
- Deduplication scope (per-source vs cross-source)
- Currency/unit handling at Silver vs Gold
- Fields present in some sources but not others (NULL strategy)
- Refresh timing mismatches across sources

**STOP**: Present open questions. Do NOT proceed to the plan until the user acknowledges them (they may answer some, defer others, or accept suggested defaults).

### Step 4: Generate Implementation Plan

**Actions:**

Produce a structured plan with these sections:

#### 4a. Bronze Prerequisites
- New Bronze tables/streams required
- Landing zone or connector setup
- Expected schema for each new source

#### 4b. Silver DT Changes
- Full column list (existing + new)
- Updated SELECT with all UNION ALL branches
- Inline SQL snippets for each transformation rule
- SOURCE_SYSTEM literal per branch
- Deduplication logic placement

#### 4c. Data Quality / Guardrails
- DMF definitions or threshold checks
- Alert conditions
- Where they live (separate from DT SQL)

#### 4d. Out of Scope (Acknowledged)
- Items explicitly deferred with rationale
- Phase/quarter reference if available

#### 4e. Suggested Testing Approach
- Row count reconciliation per source
- Dedup validation queries
- Status mapping spot-checks
- NULL/missing field audit

**STOP**: Present the full plan for final review.

### Step 5: (Optional) Generate SQL

Only if the user requests it after approving the plan:
- Generate the `CREATE OR REPLACE DYNAMIC TABLE` statement
- Include comments referencing Rule IDs (e.g., `-- BR-003: dedup`)
- Use `TARGET_LAG = DOWNSTREAM` unless user specifies otherwise

## Stopping Points

- After Step 1: Confirm requirement classification
- After Step 2: Confirm change matrix
- After Step 3: Resolve or acknowledge open questions
- After Step 4: Approve implementation plan
- After Step 5: Review generated SQL

## Best Practices

1. **Never guess business decisions.** If a rule says "OPEN QUESTION", surface it — do not pick a default silently.
2. **Preserve original values at Silver.** Unless a rule explicitly says to normalize at Silver, assume Silver stores as-is and Gold transforms.
3. **Tag every transformation with its Rule ID.** Traceability from PRD row to SQL line.
4. **Separate concerns.** DT SQL vs DMF vs Gold logic — don't conflate layers.
5. **Show your NULL strategy.** For fields that exist in some sources but not others, explicitly state they will be NULL and confirm that's acceptable.

## Output

The skill always returns these artifacts:

1. **Parsed Requirements Summary** — categorized table of all PRD rows
2. **Change Matrix** — what's new/modified in the target DT
3. **Open Questions Table** — ambiguities with suggested defaults and owners
4. **Implementation Plan** — Bronze prereqs, Silver DT changes, DQ checks, out-of-scope items, testing approach
5. **(Optional) SQL** — complete DT definition if requested

## Example Usage

```
User: I have a new PRD for AP invoices. The file is at ./requirements/ap_invoices_q3.xlsx
      and the target DT is SILVER_AP_INVOICES. Help me plan the changes.

Cortex: [Invokes prd-to-dt-plan skill]
        - Reads the XLSX file
        - Classifies rows into source onboarding, business rules, etc.
        - Presents parsed summary → user confirms
        - Identifies: 2 new sources (Baan, Workday), 3 new transformation rules,
          1 dedup rule, 1 DQ threshold
        - Surfaces 4 open questions (payment terms layer, cost center format,
          legal blocker, dedup scope)
        - Generates implementation plan with Bronze prereqs, updated UNION ALL,
          DMF definitions, and test queries
        - User approves → optionally generates full CREATE DYNAMIC TABLE SQL
```
