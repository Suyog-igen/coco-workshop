# AP Invoices PRD Review Package

Artifacts from the Q3 2025 source onboarding (Baan IV + Workday) for `SILVER_AP_INVOICES`.

---

## 1. PRD Source Files

| File | Purpose |
|------|---------|
| `sample_business_requirements_source_onboarding.csv` | New source system requests (Baan, Workday) |
| `sample_business_requirements_business_rules.csv` | Business rules BR-001 through BR-010 |
| `sample_business_requirements_column_mapping.csv` | Column-level source-to-Silver mapping |

---

## 2. Skill Definition

| File | Purpose |
|------|---------|
| `.cortex/skills/prd-to-dt-plan/SKILL.md` | Reusable project skill for converting PRD files into DT implementation plans |

**To reuse:** Provide any PRD (XLSX or CSV) and a target Dynamic Table name. Invoke with `/prd-to-dt-plan`.

---

## 3. Implementation Plan Summary

- **Target:** `SILVER_AP_INVOICES`
- **Change type:** Add 2 new UNION ALL branches (Baan IV, Workday)
- **Schema change:** None — all target columns already exist
- **Key logic:**
  - BR-001: Status normalization via CASE (per-branch)
  - BR-003: Baan dedup via QUALIFY ROW_NUMBER() on INVOICE_NUMBER
  - BR-007: SOURCE_SYSTEM literal (`'BAAN'`, `'WORKDAY'`)
  - BR-008: Drop BAN_COMPANY, WD_TENANT_ID at Silver boundary
- **Separate from DT:** BR-004 DMF for high-value invoice alerting

---

## 4. Open Questions (Must Resolve Before Production)

| # | Question | Owner | Deadline |
|---|----------|-------|----------|
| 1 | Payment terms normalization — Silver or Gold? (BR-005) | Sarah Chen + David Kim | 2025-06-20 |
| 2 | Baan cost center format (BC-XX vs BC-XXX) — pass through or normalize? | Karen van der Berg | TBD |
| 3 | Baan dedup scope — within Baan branch only, or cross-source? | Engineering | TBD |
| 4 | Workday legal blocker (DPA-2025-0041) | Jennifer Okafor / Legal | End of June |
| 5 | NULL strategy for PO_NUMBER (~15% Baan, ~10% Workday) | David Kim | TBD |
| 6 | Credit memos (negative amounts) — same table or separate? | Tom Walsh | TBD |

---

## 5. Validation Queries

Run these after deploying the updated DT to confirm correctness.

### Row count per source
```sql
SELECT SOURCE_SYSTEM, COUNT(*) AS row_count,
       MIN(CREATED_AT) AS earliest, MAX(CREATED_AT) AS latest
FROM SILVER_AP_INVOICES
GROUP BY SOURCE_SYSTEM ORDER BY SOURCE_SYSTEM;
```

### Baan dedup check (expect 0 rows)
```sql
SELECT INVOICE_NUMBER, COUNT(*) AS dupes
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM = 'BAAN'
GROUP BY INVOICE_NUMBER HAVING COUNT(*) > 1;
```

### Unmapped statuses (expect 0 rows)
```sql
SELECT SOURCE_SYSTEM, APPROVAL_STATUS, COUNT(*)
FROM SILVER_AP_INVOICES
WHERE APPROVAL_STATUS NOT IN ('APPROVED', 'PENDING')
GROUP BY 1, 2;
```

### NULL audit on required fields
```sql
SELECT SOURCE_SYSTEM,
  COUNT_IF(INVOICE_ID IS NULL)      AS null_invoice_id,
  COUNT_IF(INVOICE_NUMBER IS NULL)  AS null_invoice_number,
  COUNT_IF(VENDOR_ID IS NULL)       AS null_vendor_id,
  COUNT_IF(INVOICE_DATE IS NULL)    AS null_invoice_date,
  COUNT_IF(INVOICE_AMOUNT IS NULL)  AS null_invoice_amount,
  COUNT_IF(CURRENCY_CODE IS NULL)   AS null_currency,
  COUNT_IF(GL_ACCOUNT IS NULL)      AS null_gl_account,
  COUNT_IF(APPROVAL_STATUS IS NULL) AS null_status
FROM SILVER_AP_INVOICES
GROUP BY SOURCE_SYSTEM;
```

### Currency codes by source
```sql
SELECT SOURCE_SYSTEM, CURRENCY_CODE, COUNT(*)
FROM SILVER_AP_INVOICES GROUP BY 1, 2 ORDER BY 1, 2;
```

### SOURCE_SYSTEM completeness (expect 0)
```sql
SELECT COUNT(*) AS missing
FROM SILVER_AP_INVOICES
WHERE SOURCE_SYSTEM IS NULL OR SOURCE_SYSTEM = '';
```

### Bronze-to-Silver row loss (Baan dedup delta)
```sql
SELECT
  (SELECT COUNT(*) FROM BRONZE_AP_BAAN) AS bronze_count,
  (SELECT COUNT(*) FROM SILVER_AP_INVOICES WHERE SOURCE_SYSTEM = 'BAAN') AS silver_count,
  (SELECT COUNT(*) FROM BRONZE_AP_BAAN)
    - (SELECT COUNT(*) FROM SILVER_AP_INVOICES WHERE SOURCE_SYSTEM = 'BAAN') AS dedup_removed;
```

---

## 6. How to Reuse the PRD Evaluator Skill

```
# In any project with .cortex/skills/prd-to-dt-plan/:
# 1. Place your PRD file (XLSX or CSV) in the repo
# 2. Invoke the skill:

/prd-to-dt-plan
prd_path: path/to/your_requirements.xlsx
target_dynamic_table: YOUR_TARGET_DT

# The skill will walk through:
#   Step 1 — Parse & classify requirements
#   Step 2 — Build change matrix
#   Step 3 — Surface open questions
#   Step 4 — Generate implementation plan
#   Step 5 — (Optional) Generate CREATE DYNAMIC TABLE SQL
```
