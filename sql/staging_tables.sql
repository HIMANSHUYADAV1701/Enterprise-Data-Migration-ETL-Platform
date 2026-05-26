-- =============================================================
-- FILE: staging_tables.sql
-- PURPOSE: Create Oracle staging tables for telecom CRM migration
-- AUTHOR: Himanshu Yadav
-- =============================================================

-- Drop existing staging tables if they exist
BEGIN EXECUTE IMMEDIATE 'DROP TABLE STG_CUSTOMER_PROFILE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE STG_ACCOUNT'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE STG_SERVICE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- =============================================================
-- STG_CUSTOMER_PROFILE: Staging table for customer profile data
-- =============================================================
CREATE TABLE STG_CUSTOMER_PROFILE (
    STG_ID          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CUSTOMER_ID     VARCHAR2(20),
    FIRST_NAME      VARCHAR2(100),
    LAST_NAME       VARCHAR2(100),
    EMAIL           VARCHAR2(200),
    MOBILE_NO       VARCHAR2(20),
    DOB             VARCHAR2(20),
    GENDER          VARCHAR2(10),
    ADDRESS         VARCHAR2(500),
    CITY            VARCHAR2(100),
    STATE           VARCHAR2(100),
    PINCODE         VARCHAR2(10),
    CREATED_DATE    VARCHAR2(20),
    -- Migration control columns
    STG_LOAD_DATE   DATE         DEFAULT SYSDATE,
    STG_STATUS      VARCHAR2(20) DEFAULT 'LOADED',   -- LOADED / VALID / INVALID / PROCESSED
    STG_ERR_MSG     VARCHAR2(4000),
    SOURCE_FILE     VARCHAR2(200),
    BATCH_ID        VARCHAR2(50)
);

-- =============================================================
-- STG_ACCOUNT: Staging table for account data
-- =============================================================
CREATE TABLE STG_ACCOUNT (
    STG_ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ACCOUNT_ID          VARCHAR2(20),
    CUSTOMER_ID         VARCHAR2(20),
    ACCOUNT_TYPE        VARCHAR2(50),
    BILL_CYCLE          VARCHAR2(50),
    ACCOUNT_STATUS      VARCHAR2(50),
    CREDIT_LIMIT        VARCHAR2(20),
    BILLING_ADDRESS     VARCHAR2(500),
    BILLING_CITY        VARCHAR2(100),
    BILLING_STATE       VARCHAR2(100),
    BILLING_PINCODE     VARCHAR2(10),
    ACCOUNT_OPEN_DATE   VARCHAR2(20),
    -- Migration control columns
    STG_LOAD_DATE       DATE         DEFAULT SYSDATE,
    STG_STATUS          VARCHAR2(20) DEFAULT 'LOADED',
    STG_ERR_MSG         VARCHAR2(4000),
    SOURCE_FILE         VARCHAR2(200),
    BATCH_ID            VARCHAR2(50)
);

-- =============================================================
-- STG_SERVICE: Staging table for service data
-- =============================================================
CREATE TABLE STG_SERVICE (
    STG_ID              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SERVICE_ID          VARCHAR2(20),
    ACCOUNT_ID          VARCHAR2(20),
    SERVICE_NUMBER      VARCHAR2(20),
    SERVICE_TYPE        VARCHAR2(50),
    SERVICE_STATUS      VARCHAR2(50),
    PLAN_NAME           VARCHAR2(100),
    PLAN_TYPE           VARCHAR2(50),
    DATA_LIMIT_GB       VARCHAR2(20),
    VOICE_MINUTES       VARCHAR2(50),
    SMS_LIMIT           VARCHAR2(50),
    ACTIVATION_DATE     VARCHAR2(20),
    DEACTIVATION_DATE   VARCHAR2(20),
    -- Migration control columns
    STG_LOAD_DATE       DATE         DEFAULT SYSDATE,
    STG_STATUS          VARCHAR2(20) DEFAULT 'LOADED',
    STG_ERR_MSG         VARCHAR2(4000),
    SOURCE_FILE         VARCHAR2(200),
    BATCH_ID            VARCHAR2(50)
);

-- =============================================================
-- MIG_VALIDATION_LOG: Log table for all validation results
-- =============================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIG_VALIDATION_LOG'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE TABLE MIG_VALIDATION_LOG (
    LOG_ID          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BATCH_ID        VARCHAR2(50),
    TABLE_NAME      VARCHAR2(100),
    VALIDATION_TYPE VARCHAR2(100),
    RECORD_ID       VARCHAR2(50),
    STATUS          VARCHAR2(20),   -- PASS / FAIL
    MESSAGE         VARCHAR2(4000),
    LOG_DATE        DATE DEFAULT SYSDATE
);

-- =============================================================
-- MIG_RUN_LOG: Migration run audit log
-- =============================================================
BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIG_RUN_LOG'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
CREATE TABLE MIG_RUN_LOG (
    RUN_ID          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BATCH_ID        VARCHAR2(50),
    MIGRATION_TYPE  VARCHAR2(50),   -- PROFILE / ACCOUNT / SERVICE
    START_TIME      DATE,
    END_TIME        DATE,
    SOURCE_COUNT    NUMBER,
    LOADED_COUNT    NUMBER,
    ERROR_COUNT     NUMBER,
    STATUS          VARCHAR2(20),   -- RUNNING / SUCCESS / FAILED
    REMARKS         VARCHAR2(4000)
);

COMMIT;
PROMPT Staging tables created successfully.
