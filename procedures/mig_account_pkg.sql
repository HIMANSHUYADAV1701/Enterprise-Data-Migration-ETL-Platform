-- =============================================================
-- FILE: mig_account_pkg.sql
-- PURPOSE: PL/SQL package for account migration
--          Reads from STG_ACCOUNT → ACCOUNT
-- AUTHOR: Himanshu Yadav
-- =============================================================

CREATE OR REPLACE PACKAGE MIG_ACCOUNT_PKG AS

    PROCEDURE LOAD_ACCOUNT      (p_batch_id IN VARCHAR2 DEFAULT NULL);
    PROCEDURE VALIDATE_STAGING  (p_batch_id IN VARCHAR2);
    PROCEDURE TRANSFORM_AND_LOAD(p_batch_id IN VARCHAR2);

END MIG_ACCOUNT_PKG;
/

CREATE OR REPLACE PACKAGE BODY MIG_ACCOUNT_PKG AS

    PROCEDURE LOG_RUN (
        p_batch_id IN VARCHAR2,
        p_status   IN VARCHAR2,
        p_src_cnt  IN NUMBER DEFAULT 0,
        p_load_cnt IN NUMBER DEFAULT 0,
        p_err_cnt  IN NUMBER DEFAULT 0,
        p_remarks  IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        MERGE INTO MIG_RUN_LOG T
        USING (SELECT p_batch_id AS BATCH_ID FROM DUAL) S
        ON   (T.BATCH_ID = S.BATCH_ID AND T.MIGRATION_TYPE = 'ACCOUNT')
        WHEN MATCHED THEN UPDATE SET
            T.END_TIME = SYSDATE, T.STATUS = p_status,
            T.SOURCE_COUNT = p_src_cnt, T.LOADED_COUNT = p_load_cnt,
            T.ERROR_COUNT  = p_err_cnt, T.REMARKS = p_remarks
        WHEN NOT MATCHED THEN INSERT
            (BATCH_ID, MIGRATION_TYPE, START_TIME, STATUS, SOURCE_COUNT, LOADED_COUNT, ERROR_COUNT, REMARKS)
            VALUES (p_batch_id, 'ACCOUNT', SYSDATE, p_status, p_src_cnt, p_load_cnt, p_err_cnt, p_remarks);
        COMMIT;
    END LOG_RUN;

    -- -------------------------------------------------------
    PROCEDURE VALIDATE_STAGING (p_batch_id IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- Account Validation started: ' || p_batch_id);

        UPDATE STG_ACCOUNT
        SET    STG_STATUS = 'LOADED', STG_ERR_MSG = NULL
        WHERE  BATCH_ID = p_batch_id;

        -- ACCOUNT_ID null check
        UPDATE STG_ACCOUNT
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'ACCOUNT_ID is null'
        WHERE  BATCH_ID = p_batch_id AND ACCOUNT_ID IS NULL;

        -- CUSTOMER_ID null check
        UPDATE STG_ACCOUNT
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'CUSTOMER_ID is null'
        WHERE  BATCH_ID = p_batch_id AND CUSTOMER_ID IS NULL;

        -- ACCOUNT_TYPE valid values
        UPDATE STG_ACCOUNT
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'ACCOUNT_TYPE invalid'
        WHERE  BATCH_ID = p_batch_id
        AND    ACCOUNT_TYPE NOT IN ('Prepaid','Postpaid','Hybrid');

        -- ACCOUNT_STATUS valid values
        UPDATE STG_ACCOUNT
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'ACCOUNT_STATUS invalid'
        WHERE  BATCH_ID = p_batch_id
        AND    ACCOUNT_STATUS NOT IN ('Active','Inactive','Suspended','Closed');

        -- CUSTOMER_ID must exist in CUSTOMER_PROFILE target table
        UPDATE STG_ACCOUNT
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'CUSTOMER_ID not found in target'
        WHERE  BATCH_ID = p_batch_id
        AND    CUSTOMER_ID IS NOT NULL
        AND    TO_NUMBER(CUSTOMER_ID) NOT IN (SELECT CUSTOMER_ID FROM CUSTOMER_PROFILE);

        -- Duplicate ACCOUNT_ID check
        UPDATE STG_ACCOUNT
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'Duplicate ACCOUNT_ID'
        WHERE  BATCH_ID = p_batch_id
        AND    ACCOUNT_ID IN (
            SELECT ACCOUNT_ID FROM STG_ACCOUNT
            WHERE  BATCH_ID = p_batch_id
            GROUP BY ACCOUNT_ID HAVING COUNT(*) > 1
        )
        AND    STG_ID NOT IN (
            SELECT MIN(STG_ID) FROM STG_ACCOUNT
            WHERE  BATCH_ID = p_batch_id
            GROUP BY ACCOUNT_ID HAVING COUNT(*) > 1
        );

        -- Mark remaining as VALID
        UPDATE STG_ACCOUNT
        SET    STG_STATUS = 'VALID'
        WHERE  BATCH_ID = p_batch_id AND STG_STATUS = 'LOADED';

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('--- Account Validation completed.');
    END VALIDATE_STAGING;

    -- -------------------------------------------------------
    PROCEDURE TRANSFORM_AND_LOAD (p_batch_id IN VARCHAR2) IS
        v_loaded  NUMBER := 0;
        v_skipped NUMBER := 0;
        v_err     VARCHAR2(4000);

        CURSOR c_stg IS
            SELECT * FROM STG_ACCOUNT
            WHERE  BATCH_ID = p_batch_id AND STG_STATUS = 'VALID';
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- Account Transform & Load started: ' || p_batch_id);

        FOR r IN c_stg LOOP
            BEGIN
                MERGE INTO ACCOUNT T
                USING (SELECT TO_NUMBER(r.ACCOUNT_ID) AS ACCOUNT_ID FROM DUAL) S
                ON   (T.ACCOUNT_ID = S.ACCOUNT_ID)
                WHEN MATCHED THEN UPDATE SET
                    T.ACCOUNT_TYPE      = r.ACCOUNT_TYPE,
                    T.BILL_CYCLE        = r.BILL_CYCLE,
                    T.ACCOUNT_STATUS    = r.ACCOUNT_STATUS,
                    T.CREDIT_LIMIT      = TO_NUMBER(r.CREDIT_LIMIT),
                    T.BILLING_ADDRESS   = r.BILLING_ADDRESS,
                    T.BILLING_CITY      = r.BILLING_CITY,
                    T.BILLING_STATE     = r.BILLING_STATE,
                    T.BILLING_PINCODE   = r.BILLING_PINCODE,
                    T.ACCOUNT_OPEN_DATE = TO_DATE(r.ACCOUNT_OPEN_DATE, 'YYYY-MM-DD'),
                    T.MIG_BATCH_ID      = p_batch_id,
                    T.MIG_DATE          = SYSDATE
                WHEN NOT MATCHED THEN INSERT (
                    ACCOUNT_ID, CUSTOMER_ID, ACCOUNT_TYPE, BILL_CYCLE,
                    ACCOUNT_STATUS, CREDIT_LIMIT, BILLING_ADDRESS, BILLING_CITY,
                    BILLING_STATE, BILLING_PINCODE, ACCOUNT_OPEN_DATE,
                    MIG_BATCH_ID, MIG_DATE, RECORD_STATUS
                ) VALUES (
                    TO_NUMBER(r.ACCOUNT_ID),
                    TO_NUMBER(r.CUSTOMER_ID),
                    r.ACCOUNT_TYPE,
                    r.BILL_CYCLE,
                    r.ACCOUNT_STATUS,
                    TO_NUMBER(r.CREDIT_LIMIT),
                    r.BILLING_ADDRESS,
                    r.BILLING_CITY,
                    r.BILLING_STATE,
                    r.BILLING_PINCODE,
                    TO_DATE(r.ACCOUNT_OPEN_DATE, 'YYYY-MM-DD'),
                    p_batch_id,
                    SYSDATE,
                    'ACTIVE'
                );

                UPDATE STG_ACCOUNT SET STG_STATUS = 'PROCESSED' WHERE STG_ID = r.STG_ID;
                v_loaded := v_loaded + 1;

            EXCEPTION
                WHEN OTHERS THEN
                    v_err := SQLERRM;
                    UPDATE STG_ACCOUNT
                    SET    STG_STATUS = 'INVALID', STG_ERR_MSG = 'Transform error: ' || v_err
                    WHERE  STG_ID = r.STG_ID;
                    v_skipped := v_skipped + 1;
            END;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Loaded: ' || v_loaded || ' | Errors: ' || v_skipped);
        LOG_RUN(p_batch_id, 'SUCCESS', v_loaded + v_skipped, v_loaded, v_skipped);

    EXCEPTION
        WHEN OTHERS THEN
            v_err := SQLERRM;
            ROLLBACK;
            LOG_RUN(p_batch_id, 'FAILED', 0, 0, 0, v_err);
            RAISE;
    END TRANSFORM_AND_LOAD;

    -- -------------------------------------------------------
    PROCEDURE LOAD_ACCOUNT (p_batch_id IN VARCHAR2 DEFAULT NULL) IS
        v_batch VARCHAR2(50);
    BEGIN
        v_batch := NVL(p_batch_id, 'ACCOUNT_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS'));
        DBMS_OUTPUT.PUT_LINE('=== Starting Account Migration | Batch: ' || v_batch);
        LOG_RUN(v_batch, 'RUNNING');
        VALIDATE_STAGING(v_batch);
        TRANSFORM_AND_LOAD(v_batch);
        DBMS_OUTPUT.PUT_LINE('=== Account Migration Completed | Batch: ' || v_batch);
    END LOAD_ACCOUNT;

END MIG_ACCOUNT_PKG;
/

PROMPT MIG_ACCOUNT_PKG created successfully.
