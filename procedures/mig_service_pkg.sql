-- =============================================================
-- FILE: mig_service_pkg.sql
-- PURPOSE: PL/SQL package for service migration
--          Reads from STG_SERVICE → SERVICE
-- AUTHOR: Himanshu Yadav
-- =============================================================

CREATE OR REPLACE PACKAGE MIG_SERVICE_PKG AS

    PROCEDURE LOAD_SERVICE      (p_batch_id IN VARCHAR2 DEFAULT NULL);
    PROCEDURE VALIDATE_STAGING  (p_batch_id IN VARCHAR2);
    PROCEDURE TRANSFORM_AND_LOAD(p_batch_id IN VARCHAR2);

END MIG_SERVICE_PKG;
/

CREATE OR REPLACE PACKAGE BODY MIG_SERVICE_PKG AS

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
        ON   (T.BATCH_ID = S.BATCH_ID AND T.MIGRATION_TYPE = 'SERVICE')
        WHEN MATCHED THEN UPDATE SET
            T.END_TIME = SYSDATE, T.STATUS = p_status,
            T.SOURCE_COUNT = p_src_cnt, T.LOADED_COUNT = p_load_cnt,
            T.ERROR_COUNT  = p_err_cnt, T.REMARKS = p_remarks
        WHEN NOT MATCHED THEN INSERT
            (BATCH_ID, MIGRATION_TYPE, START_TIME, STATUS, SOURCE_COUNT, LOADED_COUNT, ERROR_COUNT, REMARKS)
            VALUES (p_batch_id, 'SERVICE', SYSDATE, p_status, p_src_cnt, p_load_cnt, p_err_cnt, p_remarks);
        COMMIT;
    END LOG_RUN;

    -- -------------------------------------------------------
    PROCEDURE VALIDATE_STAGING (p_batch_id IN VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- Service Validation started: ' || p_batch_id);

        UPDATE STG_SERVICE
        SET    STG_STATUS = 'LOADED', STG_ERR_MSG = NULL
        WHERE  BATCH_ID = p_batch_id;

        -- SERVICE_ID null check
        UPDATE STG_SERVICE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'SERVICE_ID is null'
        WHERE  BATCH_ID = p_batch_id AND SERVICE_ID IS NULL;

        -- ACCOUNT_ID null check
        UPDATE STG_SERVICE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'ACCOUNT_ID is null'
        WHERE  BATCH_ID = p_batch_id AND ACCOUNT_ID IS NULL;

        -- SERVICE_NUMBER null check
        UPDATE STG_SERVICE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'SERVICE_NUMBER is null'
        WHERE  BATCH_ID = p_batch_id AND SERVICE_NUMBER IS NULL;

        -- SERVICE_STATUS valid values
        UPDATE STG_SERVICE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'SERVICE_STATUS invalid'
        WHERE  BATCH_ID = p_batch_id
        AND    SERVICE_STATUS NOT IN ('Active','Inactive','Suspended','Terminated');

        -- ACCOUNT_ID must exist in ACCOUNT target
        UPDATE STG_SERVICE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'ACCOUNT_ID not found in target'
        WHERE  BATCH_ID = p_batch_id
        AND    ACCOUNT_ID IS NOT NULL
        AND    TO_NUMBER(ACCOUNT_ID) NOT IN (SELECT ACCOUNT_ID FROM ACCOUNT);

        -- Duplicate SERVICE_ID check
        UPDATE STG_SERVICE
        SET    STG_STATUS  = 'INVALID',
               STG_ERR_MSG = NVL(STG_ERR_MSG||' | ','') || 'Duplicate SERVICE_ID'
        WHERE  BATCH_ID = p_batch_id
        AND    SERVICE_ID IN (
            SELECT SERVICE_ID FROM STG_SERVICE
            WHERE  BATCH_ID = p_batch_id
            GROUP BY SERVICE_ID HAVING COUNT(*) > 1
        )
        AND    STG_ID NOT IN (
            SELECT MIN(STG_ID) FROM STG_SERVICE
            WHERE  BATCH_ID = p_batch_id
            GROUP BY SERVICE_ID HAVING COUNT(*) > 1
        );

        -- Mark remaining as VALID
        UPDATE STG_SERVICE
        SET    STG_STATUS = 'VALID'
        WHERE  BATCH_ID = p_batch_id AND STG_STATUS = 'LOADED';

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('--- Service Validation completed.');
    END VALIDATE_STAGING;

    -- -------------------------------------------------------
    PROCEDURE TRANSFORM_AND_LOAD (p_batch_id IN VARCHAR2) IS
        v_loaded  NUMBER := 0;
        v_skipped NUMBER := 0;
        v_err     VARCHAR2(4000);
        v_data_gb NUMBER;

        CURSOR c_stg IS
            SELECT * FROM STG_SERVICE
            WHERE  BATCH_ID = p_batch_id AND STG_STATUS = 'VALID';
    BEGIN
        DBMS_OUTPUT.PUT_LINE('--- Service Transform & Load started: ' || p_batch_id);

        FOR r IN c_stg LOOP
            BEGIN
                -- Handle DATA_LIMIT_GB — may be numeric or 'Unlimited'
                BEGIN
                    v_data_gb := TO_NUMBER(r.DATA_LIMIT_GB);
                EXCEPTION
                    WHEN OTHERS THEN v_data_gb := NULL;
                END;

                MERGE INTO SERVICE T
                USING (SELECT TO_NUMBER(r.SERVICE_ID) AS SERVICE_ID FROM DUAL) S
                ON   (T.SERVICE_ID = S.SERVICE_ID)
                WHEN MATCHED THEN UPDATE SET
                    T.SERVICE_STATUS    = r.SERVICE_STATUS,
                    T.PLAN_NAME         = r.PLAN_NAME,
                    T.PLAN_TYPE         = r.PLAN_TYPE,
                    T.DATA_LIMIT_GB     = v_data_gb,
                    T.VOICE_MINUTES     = r.VOICE_MINUTES,
                    T.SMS_LIMIT         = r.SMS_LIMIT,
                    T.ACTIVATION_DATE   = TO_DATE(r.ACTIVATION_DATE, 'YYYY-MM-DD'),
                    T.DEACTIVATION_DATE = CASE WHEN r.DEACTIVATION_DATE IS NOT NULL AND r.DEACTIVATION_DATE != ''
                                               THEN TO_DATE(r.DEACTIVATION_DATE, 'YYYY-MM-DD')
                                               ELSE NULL END,
                    T.MIG_BATCH_ID      = p_batch_id,
                    T.MIG_DATE          = SYSDATE
                WHEN NOT MATCHED THEN INSERT (
                    SERVICE_ID, ACCOUNT_ID, SERVICE_NUMBER, SERVICE_TYPE,
                    SERVICE_STATUS, PLAN_NAME, PLAN_TYPE, DATA_LIMIT_GB,
                    VOICE_MINUTES, SMS_LIMIT, ACTIVATION_DATE, DEACTIVATION_DATE,
                    MIG_BATCH_ID, MIG_DATE, RECORD_STATUS
                ) VALUES (
                    TO_NUMBER(r.SERVICE_ID),
                    TO_NUMBER(r.ACCOUNT_ID),
                    r.SERVICE_NUMBER,
                    r.SERVICE_TYPE,
                    r.SERVICE_STATUS,
                    r.PLAN_NAME,
                    r.PLAN_TYPE,
                    v_data_gb,
                    r.VOICE_MINUTES,
                    r.SMS_LIMIT,
                    TO_DATE(r.ACTIVATION_DATE, 'YYYY-MM-DD'),
                    CASE WHEN r.DEACTIVATION_DATE IS NOT NULL AND r.DEACTIVATION_DATE != ''
                         THEN TO_DATE(r.DEACTIVATION_DATE, 'YYYY-MM-DD')
                         ELSE NULL END,
                    p_batch_id,
                    SYSDATE,
                    'ACTIVE'
                );

                UPDATE STG_SERVICE SET STG_STATUS = 'PROCESSED' WHERE STG_ID = r.STG_ID;
                v_loaded := v_loaded + 1;

            EXCEPTION
                WHEN OTHERS THEN
                    v_err := SQLERRM;
                    UPDATE STG_SERVICE
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
    PROCEDURE LOAD_SERVICE (p_batch_id IN VARCHAR2 DEFAULT NULL) IS
        v_batch VARCHAR2(50);
    BEGIN
        v_batch := NVL(p_batch_id, 'SERVICE_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS'));
        DBMS_OUTPUT.PUT_LINE('=== Starting Service Migration | Batch: ' || v_batch);
        LOG_RUN(v_batch, 'RUNNING');
        VALIDATE_STAGING(v_batch);
        TRANSFORM_AND_LOAD(v_batch);
        DBMS_OUTPUT.PUT_LINE('=== Service Migration Completed | Batch: ' || v_batch);
    END LOAD_SERVICE;

END MIG_SERVICE_PKG;
/

PROMPT MIG_SERVICE_PKG created successfully.
