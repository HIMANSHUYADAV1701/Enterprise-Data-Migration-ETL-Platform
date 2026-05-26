-- =============================================================
-- FILE: views.sql
-- PURPOSE: Create Oracle views for CRM data exposure
-- AUTHOR: Himanshu Yadav
-- =============================================================

-- Drop existing views
BEGIN EXECUTE IMMEDIATE 'DROP VIEW VW_CRM_FULL_PROFILE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW VW_SERVICE_ACCOUNT'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW VW_ACCOUNT_PROFILE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP VIEW VW_CUSTOMER_PROFILE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- =============================================================
-- VW_CUSTOMER_PROFILE: Clean profile view for CRM
-- =============================================================
CREATE OR REPLACE VIEW VW_CUSTOMER_PROFILE AS
SELECT
    PROFILE_ID,
    CUSTOMER_ID,
    FIRST_NAME,
    LAST_NAME,
    FULL_NAME,
    EMAIL,
    MOBILE_NO,
    TO_CHAR(DOB, 'YYYY-MM-DD')          AS DOB,
    GENDER,
    ADDRESS,
    CITY,
    STATE,
    PINCODE,
    TO_CHAR(CREATED_DATE, 'YYYY-MM-DD') AS CREATED_DATE,
    RECORD_STATUS
FROM
    CUSTOMER_PROFILE
WHERE
    RECORD_STATUS = 'ACTIVE';

-- =============================================================
-- VW_ACCOUNT_PROFILE: Account joined with profile
-- =============================================================
CREATE OR REPLACE VIEW VW_ACCOUNT_PROFILE AS
SELECT
    A.ACCOUNT_ID,
    A.CUSTOMER_ID,
    P.FULL_NAME,
    P.MOBILE_NO,
    P.EMAIL,
    A.ACCOUNT_TYPE,
    A.BILL_CYCLE,
    A.ACCOUNT_STATUS,
    A.CREDIT_LIMIT,
    A.BILLING_CITY,
    A.BILLING_STATE,
    TO_CHAR(A.ACCOUNT_OPEN_DATE, 'YYYY-MM-DD') AS ACCOUNT_OPEN_DATE
FROM
    ACCOUNT          A
    JOIN CUSTOMER_PROFILE P ON A.CUSTOMER_ID = P.CUSTOMER_ID
WHERE
    A.RECORD_STATUS = 'ACTIVE'
    AND P.RECORD_STATUS = 'ACTIVE';

-- =============================================================
-- VW_SERVICE_ACCOUNT: Service joined with account
-- =============================================================
CREATE OR REPLACE VIEW VW_SERVICE_ACCOUNT AS
SELECT
    S.SERVICE_ID,
    S.ACCOUNT_ID,
    A.CUSTOMER_ID,
    S.SERVICE_NUMBER,
    S.SERVICE_TYPE,
    S.SERVICE_STATUS,
    S.PLAN_NAME,
    S.PLAN_TYPE,
    S.DATA_LIMIT_GB,
    S.VOICE_MINUTES,
    S.SMS_LIMIT,
    TO_CHAR(S.ACTIVATION_DATE,   'YYYY-MM-DD') AS ACTIVATION_DATE,
    TO_CHAR(S.DEACTIVATION_DATE, 'YYYY-MM-DD') AS DEACTIVATION_DATE
FROM
    SERVICE  S
    JOIN ACCOUNT A ON S.ACCOUNT_ID = A.ACCOUNT_ID
WHERE
    S.RECORD_STATUS = 'ACTIVE'
    AND A.RECORD_STATUS = 'ACTIVE';

-- =============================================================
-- VW_CRM_FULL_PROFILE: Full 360-degree CRM view
-- =============================================================
CREATE OR REPLACE VIEW VW_CRM_FULL_PROFILE AS
SELECT
    P.CUSTOMER_ID,
    P.FULL_NAME,
    P.EMAIL,
    P.MOBILE_NO,
    P.CITY,
    P.STATE,
    A.ACCOUNT_ID,
    A.ACCOUNT_TYPE,
    A.ACCOUNT_STATUS,
    A.BILL_CYCLE,
    S.SERVICE_ID,
    S.SERVICE_NUMBER,
    S.SERVICE_STATUS,
    S.PLAN_NAME,
    S.PLAN_TYPE,
    TO_CHAR(S.ACTIVATION_DATE, 'YYYY-MM-DD') AS ACTIVATION_DATE
FROM
    CUSTOMER_PROFILE P
    JOIN ACCOUNT  A ON P.CUSTOMER_ID  = A.CUSTOMER_ID
    JOIN SERVICE  S ON A.ACCOUNT_ID   = S.ACCOUNT_ID
WHERE
    P.RECORD_STATUS = 'ACTIVE'
    AND A.RECORD_STATUS = 'ACTIVE'
    AND S.RECORD_STATUS = 'ACTIVE';

COMMIT;
PROMPT Views created successfully.
