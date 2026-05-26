-- =============================================================
-- FILE: packages.sql
-- PURPOSE: Master script to compile all migration packages
--          Run this after target_tables.sql
-- AUTHOR: Himanshu Yadav
-- =============================================================

PROMPT Compiling MIG_PROFILE_PKG...
@@../procedures/mig_profile_pkg.sql

PROMPT Compiling MIG_ACCOUNT_PKG...
@@../procedures/mig_account_pkg.sql

PROMPT Compiling MIG_SERVICE_PKG...
@@../procedures/mig_service_pkg.sql

PROMPT
PROMPT =====================================================
PROMPT All migration packages compiled successfully.
PROMPT =====================================================
PROMPT
PROMPT To run migration:
PROMPT
PROMPT   BEGIN MIG_PROFILE_PKG.LOAD_CUSTOMER_PROFILE; END;
PROMPT   BEGIN MIG_ACCOUNT_PKG.LOAD_ACCOUNT;          END;
PROMPT   BEGIN MIG_SERVICE_PKG.LOAD_SERVICE;          END;
PROMPT
