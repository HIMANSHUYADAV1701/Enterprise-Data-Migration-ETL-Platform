-- =============================================================
-- FILE: mig_profile_pkg.sql
-- PURPOSE: PL/SQL package for customer profile migration
--          Reads from STG_CUSTOMER_PROFILE → CUSTOMER_PROFILE
-- AUTHOR: Himanshu Yadav
-- =============================================================

CREATE OR REPLACE PACKAGE MIG_PROFILE_PKG AS

    -- Main entry point
    PROCEDURE LOAD_CUSTOMER_PROFILE (p_batch_id IN VARCHAR2 DEFAULT NULL);

    -- Validate staging records
    PROCEDURE VALIDATE_STAGING (p_batch_id IN VARCHAR2);

    -- Transform and load to target
    PROCEDURE TRANSFORM_AND_LOAD (p_batch_id IN VARCHAR2);

END MIG_PROFILE_PKG;
/

CREATE OR REPLACE PACKAGE BODY MIG_PROFILE_PKG AS

    -- -------------------------------------------------------
    -- Private: Log a migration run entry
    -- -------------------------------------------------------
    PROCEDURE LOG_RUN (
        p_batch_id   IN VARCHAR2,
        p_status     IN VARCHAR2,
        p_src_cnt    IN NUMBER DEFAULT 0,
        p_load_cnt   IN NUMBER DEFAULT 0,
        p_err_cnt    IN NUMBER DEFAULT 0,
        p_remarks    IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        MERGE INTO MIG_RUN_LOG T
        USING (SELECT p_batch_id AS BATCH_ID FROM DUAL) S
        ON    (T.BATCH_ID = S.BATCH_ID AND T.MIGRATION_TYPE = 'PROFILE')
        WHEN MATCHED THEN UPDATE SET
            T.END_TIME     = SYSDATE,
            T.STATUS       = p_status,
            T.SOURCE_COUNT = p_src_cnt,
            T.LOADED_COUNT = p_load_cnt,
            T.ERROR_COUNT  = p_err_cnt,
            T.REMARKS      = p_remarks
        WHEN NOT MATCHED THEN INSERT (BATCH_ID, MIGRATION_TYPE, START_TIME, STATUS, SOURCE_COUNT, LOADED_COUNT, ERROR_COUNT, REMARKS)
            VALUES (p_batch_id, 'PROFILE', SYSDATE, p_status, p_src_cnt, p_load_cnt, p_err_cnt, p_remarks);
        COMMIT;
    END LOG_RUN;

    -- -------------------------------------------------------
    -- VALIDATE_STAGING: Mark records VALID / INVALID in staging
    -- -------------------------------------------------------
    PROCEDURE VALIDATE_STAGING (p_batch_id IN VARCHAR2) IS
        v_err VARCHAR2(4000);
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- Profile Validation started for batch: ' || p_batch_id);

        -- Reset all to LOADED
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS = 'LOADED', STG_ERR_MSG = NULL
        WHERE  BATCH_ID = p_batch_id;

        -- Check CUSTOMER_ID not null
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'CUSTOMER_ID is null'
        WHERE  BATCH_ID = p_batch_id AND CUSTOMER_ID IS NULL;

        -- Check MOBILE_NO not null
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'MOBILE_NO is null'
        WHERE  BATCH_ID = p_batch_id AND MOBILE_NO IS NULL;

        -- Check FIRST_NAME not null
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'FIRST_NAME is null'
        WHERE  BATCH_ID = p_batch_id AND FIRST_NAME IS NULL;

        -- Check LAST_NAME not null
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'LAST_NAME is null'
        WHERE  BATCH_ID = p_batch_id AND LAST_NAME IS NULL;

        -- Check MOBILE_NO length = 10
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'MOBILE_NO invalid length'
        WHERE  BATCH_ID = p_batch_id
        AND    MOBILE_NO IS NOT NULL
        AND    LENGTH(MOBILE_NO) != 10;

        -- Check GENDER valid values
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'GENDER invalid value'
        WHERE  BATCH_ID = p_batch_id
        AND    GENDER IS NOT NULL
        AND    GENDER NOT IN ('M','F','O');

        -- Check duplicate CUSTOMER_ID within batch
        UPDATE STG_CUSTOMER_PROFILE S
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'Duplicate CUSTOMER_ID in batch'
        WHERE  BATCH_ID = p_batch_id
        AND    CUSTOMER_ID IN (
            SELECT CUSTOMER_ID FROM STG_CUSTOMER_PROFILE
            WHERE  BATCH_ID = p_batch_id
            GROUP BY CUSTOMER_ID HAVING COUNT(*) > 1
        )
        AND    STG_ID NOT IN (
            SELECT MIN(STG_ID) FROM STG_CUSTOMER_PROFILE
            WHERE  BATCH_ID = p_batch_id
            GROUP BY CUSTOMER_ID HAVING COUNT(*) > 1
        );

        -- Mark remaining as VALID
        UPDATE STG_CUSTOMER_PROFILE
        SET    STG_STATUS = 'VALID'
        WHERE  BATCH_ID = p_batch_id AND STG_STATUS = 'LOADED';

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('--- Profile Validation completed.');

    EXCEPTION
        WHEN OTHERS THEN
            v_err := SQLERRM;
            DBMS_OUTPUT.PUT_LINE('ERROR in VALIDATE_STAGING: ' || v_err);
            RAISE;
    END VALIDATE_STAGING;

    -- -------------------------------------------------------
    -- TRANSFORM_AND_LOAD: Move VALID records to target
    -- -------------------------------------------------------
    PROCEDURE TRANSFORM_AND_LOAD (p_batch_id IN VARCHAR2) IS
        v_loaded  NUMBER := 0;
        v_skipped NUMBER := 0;
        v_err     VARCHAR2(4000);

        CURSOR c_stg IS
            SELECT *
            FROM   STG_CUSTOMER_PROFILE
            WHERE  BATCH_ID   = p_batch_id
            AND    STG_STATUS = 'VALID';
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- Profile Transform & Load started for batch: ' || p_batch_id);

        FOR r IN c_stg LOOP
            BEGIN
                -- MERGE to avoid duplicates on re-run
                MERGE INTO CUSTOMER_PROFILE T
                USING (SELECT TO_NUMBER(r.CUSTOMER_ID) AS CUSTOMER_ID FROM DUAL) S
                ON   (T.CUSTOMER_ID = S.CUSTOMER_ID)
                WHEN MATCHED THEN UPDATE SET
                    T.FIRST_NAME    = INITCAP(r.FIRST_NAME),
                    T.LAST_NAME     = INITCAP(r.LAST_NAME),
                    T.FULL_NAME     = INITCAP(r.FIRST_NAME) || ' ' || INITCAP(r.LAST_NAME),
                    T.EMAIL         = LOWER(r.EMAIL),
                    T.MOBILE_NO     = r.MOBILE_NO,
                    T.DOB           = TO_DATE(r.DOB, 'YYYY-MM-DD'),
                    T.GENDER        = UPPER(r.GENDER),
                    T.ADDRESS       = r.ADDRESS,
                    T.CITY          = r.CITY,
                    T.STATE         = r.STATE,
                    T.PINCODE       = r.PINCODE,
                    T.MIG_BATCH_ID  = p_batch_id,
                    T.MIG_DATE      = SYSDATE
                WHEN NOT MATCHED THEN INSERT (
                    CUSTOMER_ID, FIRST_NAME, LAST_NAME, FULL_NAME,
                    EMAIL, MOBILE_NO, DOB, GENDER, ADDRESS,
                    CITY, STATE, PINCODE, CREATED_DATE,
                    MIG_BATCH_ID, MIG_DATE, RECORD_STATUS
                ) VALUES (
                    TO_NUMBER(r.CUSTOMER_ID),
                    INITCAP(r.FIRST_NAME),
                    INITCAP(r.LAST_NAME),
                    INITCAP(r.FIRST_NAME) || ' ' || INITCAP(r.LAST_NAME),
                    LOWER(r.EMAIL),
                    r.MOBILE_NO,
                    TO_DATE(r.DOB, 'YYYY-MM-DD'),
                    UPPER(r.GENDER),
                    r.ADDRESS,
                    r.CITY,
                    r.STATE,
                    r.PINCODE,
                    TO_DATE(r.CREATED_DATE, 'YYYY-MM-DD'),
                    p_batch_id,
                    SYSDATE,
                    'ACTIVE'
                );

                -- Mark staging record as PROCESSED
                UPDATE STG_CUSTOMER_PROFILE
                SET    STG_STATUS = 'PROCESSED'
                WHERE  STG_ID = r.STG_ID;

                v_loaded := v_loaded + 1;

            EXCEPTION
                WHEN OTHERS THEN
                    v_err := SQLERRM;
                    UPDATE STG_CUSTOMER_PROFILE
                    SET    STG_STATUS  = 'INVALID',
                           STG_ERR_MSG = 'Transform error: ' || v_err
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
            DBMS_OUTPUT.PUT_LINE('ERROR in TRANSFORM_AND_LOAD: ' || v_err);
            RAISE;
    END TRANSFORM_AND_LOAD;

    -- -------------------------------------------------------
    -- LOAD_CUSTOMER_PROFILE: Main procedure (calls validate + load)
    -- -------------------------------------------------------
    PROCEDURE LOAD_CUSTOMER_PROFILE (p_batch_id IN VARCHAR2 DEFAULT NULL) IS
        v_batch VARCHAR2(50);
    BEGIN
        v_batch := NVL(p_batch_id, 'PROFILE_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS'));
        DBMS_OUTPUT.PUT_LINE('=== Starting Profile Migration | Batch: ' || v_batch);
        LOG_RUN(v_batch, 'RUNNING');

        VALIDATE_STAGING(v_batch);
        TRANSFORM_AND_LOAD(v_batch);

        DBMS_OUTPUT.PUT_LINE('=== Profile Migration Completed | Batch: ' || v_batch);
    END LOAD_CUSTOMER_PROFILE;

END MIG_PROFILE_PKG;
/

PROMPT MIG_PROFILE_PKG created successfully.
