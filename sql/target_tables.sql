-- =============================================================
-- FILE: target_tables.sql
-- PURPOSE: Create Oracle target tables for telecom CRM migration
-- AUTHOR: Himanshu Yadav
-- =============================================================

-- Drop existing target tables
BEGIN EXECUTE IMMEDIATE 'DROP TABLE SERVICE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE ACCOUNT'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
BEGIN EXECUTE IMMEDIATE 'DROP TABLE CUSTOMER_PROFILE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/

-- =============================================================
-- CUSTOMER_PROFILE: Target table for customer profile
-- =============================================================
CREATE TABLE CUSTOMER_PROFILE (
    PROFILE_ID      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CUSTOMER_ID     NUMBER          NOT NULL,
    FIRST_NAME      VARCHAR2(100)   NOT NULL,
    LAST_NAME       VARCHAR2(100)   NOT NULL,
    FULL_NAME       VARCHAR2(200),
    EMAIL           VARCHAR2(200),
    MOBILE_NO       VARCHAR2(20)    NOT NULL,
    DOB             DATE,
    GENDER          VARCHAR2(10),
    ADDRESS         VARCHAR2(500),
    CITY            VARCHAR2(100),
    STATE           VARCHAR2(100),
    PINCODE         VARCHAR2(10),
    CREATED_DATE    DATE,
    -- Audit columns
    MIG_BATCH_ID    VARCHAR2(50),
    MIG_DATE        DATE DEFAULT SYSDATE,
    RECORD_STATUS   VARCHAR2(20) DEFAULT 'ACTIVE',
    CONSTRAINT UK_CUSTOMER_ID UNIQUE (CUSTOMER_ID)
);

-- =============================================================
-- ACCOUNT: Target table for account
-- =============================================================
CREATE TABLE ACCOUNT (
    ACCOUNT_ID          NUMBER          NOT NULL,
    CUSTOMER_ID         NUMBER          NOT NULL,
    ACCOUNT_TYPE        VARCHAR2(50),
    BILL_CYCLE          VARCHAR2(50),
    ACCOUNT_STATUS      VARCHAR2(50),
    CREDIT_LIMIT        NUMBER,
    BILLING_ADDRESS     VARCHAR2(500),
    BILLING_CITY        VARCHAR2(100),
    BILLING_STATE       VARCHAR2(100),
    BILLING_PINCODE     VARCHAR2(10),
    ACCOUNT_OPEN_DATE   DATE,
    -- Audit columns
    MIG_BATCH_ID        VARCHAR2(50),
    MIG_DATE            DATE DEFAULT SYSDATE,
    RECORD_STATUS       VARCHAR2(20) DEFAULT 'ACTIVE',
    CONSTRAINT PK_ACCOUNT PRIMARY KEY (ACCOUNT_ID),
    CONSTRAINT FK_ACCOUNT_CUSTOMER FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER_PROFILE (CUSTOMER_ID)
);

-- =============================================================
-- SERVICE: Target table for service
-- =============================================================
CREATE TABLE SERVICE (
    SERVICE_ID          NUMBER          NOT NULL,
    ACCOUNT_ID          NUMBER          NOT NULL,
    SERVICE_NUMBER      VARCHAR2(20),
    SERVICE_TYPE        VARCHAR2(50),
    SERVICE_STATUS      VARCHAR2(50),
    PLAN_NAME           VARCHAR2(100),
    PLAN_TYPE           VARCHAR2(50),
    DATA_LIMIT_GB       NUMBER,
    VOICE_MINUTES       VARCHAR2(50),
    SMS_LIMIT           VARCHAR2(50),
    ACTIVATION_DATE     DATE,
    DEACTIVATION_DATE   DATE,
    -- Audit columns
    MIG_BATCH_ID        VARCHAR2(50),
    MIG_DATE            DATE DEFAULT SYSDATE,
    RECORD_STATUS       VARCHAR2(20) DEFAULT 'ACTIVE',
    CONSTRAINT PK_SERVICE PRIMARY KEY (SERVICE_ID),
    CONSTRAINT FK_SERVICE_ACCOUNT FOREIGN KEY (ACCOUNT_ID) REFERENCES ACCOUNT (ACCOUNT_ID)
);

-- Indexes for performance
CREATE INDEX IDX_ACCT_CUSTOMER_ID  ON ACCOUNT  (CUSTOMER_ID);
CREATE INDEX IDX_SVC_ACCOUNT_ID    ON SERVICE  (ACCOUNT_ID);
CREATE INDEX IDX_SVC_SVC_NUMBER    ON SERVICE  (SERVICE_NUMBER);

COMMIT;
PROMPT Target tables created successfully.
