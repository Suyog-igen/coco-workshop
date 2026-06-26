-- =============================================================================
-- SILVER_AP_INVOICES Dynamic Table
-- Consolidates AP invoice data from SAP, Oracle, Baan IV, and Workday
-- into a unified Silver-layer schema.
--
-- Business Rules Applied:
--   BR-001: Status normalization (CASE per branch)
--   BR-003: Baan dedup on INVOICE_NUMBER (QUALIFY ROW_NUMBER)
--   BR-007: SOURCE_SYSTEM literal per branch
--   BR-008: System-specific columns dropped
--
-- NOT applied here (separate concerns):
--   BR-002: Currency conversion (Gold layer)
--   BR-004: High-value invoice DMF (Guardrails Pack)
--   BR-005: Payment terms normalization (Gold layer, pending decision)
--   BR-006: GL account cross-reference (Gold layer, Phase 2)
-- =============================================================================

CREATE OR REPLACE DYNAMIC TABLE SILVER_AP_INVOICES
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = TRANSFORM_WH
AS

-- ============================================================
-- SAP branch
-- ============================================================
SELECT
  SAP_INVOICE_ID        AS INVOICE_ID,
  SAP_INVOICE_NUM       AS INVOICE_NUMBER,
  SAP_VENDOR_ID         AS VENDOR_ID,
  SAP_VENDOR_NAME       AS VENDOR_NAME,
  SAP_INVOICE_DATE      AS INVOICE_DATE,
  SAP_DUE_DATE          AS DUE_DATE,
  SAP_AMOUNT            AS INVOICE_AMOUNT,
  SAP_CURRENCY          AS CURRENCY_CODE,
  SAP_PAY_TERMS         AS PAYMENT_TERMS,
  SAP_PO_NUMBER         AS PO_NUMBER,
  SAP_LINE_DESC         AS LINE_DESCRIPTION,
  SAP_GL_ACCOUNT        AS GL_ACCOUNT,
  SAP_COST_CENTER       AS COST_CENTER,
  -- BR-001: SAP statuses map directly
  CASE SAP_STATUS
    WHEN 'APPROVED' THEN 'APPROVED'
    WHEN 'PENDING'  THEN 'PENDING'
    ELSE 'PENDING'
  END                   AS APPROVAL_STATUS,
  SAP_CREATED_AT        AS CREATED_AT,
  'SAP'                 AS SOURCE_SYSTEM
FROM BRONZE_AP_SAP

UNION ALL

-- ============================================================
-- Oracle branch
-- ============================================================
SELECT
  ORACLE_INVOICE_ID     AS INVOICE_ID,
  ORACLE_INVOICE_NUM    AS INVOICE_NUMBER,
  ORACLE_VENDOR_ID      AS VENDOR_ID,
  ORACLE_VENDOR_NAME    AS VENDOR_NAME,
  ORACLE_INVOICE_DATE   AS INVOICE_DATE,
  ORACLE_DUE_DATE       AS DUE_DATE,
  ORACLE_AMOUNT         AS INVOICE_AMOUNT,
  ORACLE_CURRENCY       AS CURRENCY_CODE,
  ORACLE_PAY_TERMS      AS PAYMENT_TERMS,
  ORACLE_PO_NUMBER      AS PO_NUMBER,
  ORACLE_LINE_DESC      AS LINE_DESCRIPTION,
  ORACLE_GL_ACCOUNT     AS GL_ACCOUNT,
  ORACLE_COST_CENTER    AS COST_CENTER,
  -- BR-001: VALIDATED → APPROVED
  CASE ORACLE_STATUS
    WHEN 'VALIDATED' THEN 'APPROVED'
    WHEN 'PENDING'   THEN 'PENDING'
    ELSE 'PENDING'
  END                   AS APPROVAL_STATUS,
  ORACLE_CREATED_AT     AS CREATED_AT,
  'ORACLE'              AS SOURCE_SYSTEM
FROM BRONZE_AP_ORACLE

UNION ALL

-- ============================================================
-- Baan IV branch
-- BR-003: Deduplicate on INVOICE_NUMBER (latest CREATED_AT wins)
-- ============================================================
SELECT
  BAN_INVOICE_ID        AS INVOICE_ID,
  BAN_INVOICE_REF       AS INVOICE_NUMBER,
  BAN_VENDOR_CODE       AS VENDOR_ID,
  BAN_VENDOR_DESC       AS VENDOR_NAME,
  BAN_INV_DATE          AS INVOICE_DATE,
  BAN_PAY_DATE          AS DUE_DATE,
  BAN_AMOUNT            AS INVOICE_AMOUNT,
  BAN_CURR              AS CURRENCY_CODE,
  BAN_PAY_TERMS         AS PAYMENT_TERMS,
  BAN_PO_REF            AS PO_NUMBER,
  BAN_LINE_DESC         AS LINE_DESCRIPTION,
  BAN_GL_CODE           AS GL_ACCOUNT,
  BAN_COST_CTR          AS COST_CENTER,
  -- BR-001: POSTED → APPROVED
  CASE BAN_STATUS
    WHEN 'POSTED'   THEN 'APPROVED'
    WHEN 'APPROVED' THEN 'APPROVED'
    WHEN 'PENDING'  THEN 'PENDING'
    ELSE 'PENDING'
  END                   AS APPROVAL_STATUS,
  BAN_CREATED           AS CREATED_AT,
  'BAAN'                AS SOURCE_SYSTEM
FROM BRONZE_AP_BAAN
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY BAN_INVOICE_REF
  ORDER BY BAN_CREATED DESC
) = 1

UNION ALL

-- ============================================================
-- Workday branch
-- ============================================================
SELECT
  WD_INVOICE_ID         AS INVOICE_ID,
  WD_INVOICE_NUM        AS INVOICE_NUMBER,
  WD_SUPPLIER_ID        AS VENDOR_ID,
  WD_SUPPLIER_NAME      AS VENDOR_NAME,
  WD_INVOICE_DATE       AS INVOICE_DATE,
  WD_DUE_DATE           AS DUE_DATE,
  WD_AMOUNT             AS INVOICE_AMOUNT,
  WD_CURRENCY           AS CURRENCY_CODE,
  WD_PAY_TERMS          AS PAYMENT_TERMS,
  WD_PO_NUMBER          AS PO_NUMBER,
  WD_MEMO               AS LINE_DESCRIPTION,
  WD_LEDGER_ACCOUNT     AS GL_ACCOUNT,
  WD_COST_CENTER        AS COST_CENTER,
  -- BR-001: Approved → APPROVED, In Review → PENDING
  CASE WD_APPROVAL_STATUS
    WHEN 'Approved'  THEN 'APPROVED'
    WHEN 'In Review' THEN 'PENDING'
    ELSE 'PENDING'
  END                   AS APPROVAL_STATUS,
  WD_CREATED_DATE       AS CREATED_AT,
  'WORKDAY'             AS SOURCE_SYSTEM
FROM BRONZE_AP_WORKDAY
;
