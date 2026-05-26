# Telecom CRM Data Migration Platform

## Overview

End-to-end telecom CRM data migration platform that migrates customer data from legacy flat files into Oracle staging tables, transforms data using PL/SQL packages, validates records through a Python framework, and loads CRM-ready JSON documents into MongoDB collections.

```text
Flat File → Oracle Staging → Validation → PL/SQL Transformation → Oracle Target → Oracle Views → MongoDB CRM Collections
```

Covers Profile → Account → Service migration with full validation and reconciliation.

---

## Architecture

```text
Source Flat Files
       │
       ▼
Python File Loader  (load_flatfile_to_staging.py)
       │
       ▼
Oracle Staging Tables  (STG_CUSTOMER_PROFILE / STG_ACCOUNT / STG_SERVICE)
       │
       ▼
Python Validation Framework  (data_validation.py)
       │
       ▼
PL/SQL Packages  (MIG_PROFILE_PKG / MIG_ACCOUNT_PKG / MIG_SERVICE_PKG)
       │
       ▼
Oracle Target Tables  (CUSTOMER_PROFILE / ACCOUNT / SERVICE)
       │
       ▼
Oracle Views  (VW_CUSTOMER_PROFILE / VW_ACCOUNT_PROFILE / VW_SERVICE_ACCOUNT / VW_CRM_FULL_PROFILE)
       │
       ▼
Python MongoDB Loader  (oracle_to_mongodb.py)
       │
       ▼
MongoDB CRM Collections  (crm_profiles / crm_accounts / crm_services / crm_full_360)
       │
       ▼
Python Reconciliation  (mongodb_compare.py)
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Python 3.10+ |
| Oracle DB | Oracle 19c / 21c |
| PL/SQL | Oracle PL/SQL packages |
| MongoDB | MongoDB 6+ |
| Python libs | cx_Oracle, PyMongo, Pandas |

---

## Repository Structure

```text
telecom-crm-migration-platform/
│
├── README.md
├── requirements.txt
│
├── source_files/
│   ├── customer_profile.csv       ← Source profile flat file
│   ├── account_data.csv           ← Source account flat file
│   └── service_data.csv           ← Source service flat file
│
├── sql/
│   ├── staging_tables.sql         ← STG_* tables + MIG_VALIDATION_LOG + MIG_RUN_LOG
│   ├── target_tables.sql          ← CUSTOMER_PROFILE / ACCOUNT / SERVICE target tables
│   ├── views.sql                  ← Oracle views for CRM data exposure
│   └── packages.sql               ← Master compile script for all PL/SQL packages
│
├── procedures/
│   ├── mig_profile_pkg.sql        ← Profile migration PL/SQL package
│   ├── mig_account_pkg.sql        ← Account migration PL/SQL package
│   └── mig_service_pkg.sql        ← Service migration PL/SQL package
│
├── python/
│   ├── load_flatfile_to_staging.py  ← CSV → Oracle Staging loader
│   ├── data_validation.py           ← Python validation framework
│   ├── oracle_to_mongodb.py         ← Oracle views → MongoDB loader
│   └── mongodb_compare.py           ← Oracle ↔ MongoDB reconciliation
│
├── configs/
│   └── db_config.json             ← Oracle + MongoDB connection config
│
└── docs/
    └── architecture.png           ← Architecture diagram (optional)
```

---

## Migration Flow

### 1. Flat File Ingestion

CSV source files are read using Pandas and bulk-inserted into Oracle staging tables using `cx_Oracle.executemany`. Each row gets a `BATCH_ID`, `SOURCE_FILE`, and an initial `STG_STATUS = 'LOADED'`.

### 2. Python Validation Layer

`data_validation.py` performs checks directly against staging tables before PL/SQL runs:

| Check | Description |
|---|---|
| Null check | Mandatory fields must not be null |
| Duplicate check | Key columns must be unique within batch |
| Valid value check | Enum columns checked against allowed values |
| Referential integrity | FK columns must exist in parent table |
| Row count recon | Staged count must match source file count |
| Invalid record count | Staging records with INVALID status flagged |

All results are logged to `MIG_VALIDATION_LOG` in Oracle and to `logs/data_validation.log`.

### 3. PL/SQL Transformation Layer

Each package (`MIG_PROFILE_PKG`, `MIG_ACCOUNT_PKG`, `MIG_SERVICE_PKG`) runs in two phases:

**VALIDATE_STAGING** — updates STG_STATUS to VALID/INVALID with error messages.

**TRANSFORM_AND_LOAD** — cursors through VALID records, applies transformations (INITCAP names, LOWER email, date casting, numeric casting), and MERGEs into target tables. Each processed row is marked `STG_STATUS = 'PROCESSED'`.

Transformations applied:
- `FULL_NAME = INITCAP(FIRST_NAME) || ' ' || INITCAP(LAST_NAME)`
- `EMAIL = LOWER(EMAIL)`
- All string dates cast to Oracle DATE using `TO_DATE(..., 'YYYY-MM-DD')`
- `DATA_LIMIT_GB` handles both numeric values and 'Unlimited' gracefully

### 4. Oracle Target Tables

Clean normalised relational tables with foreign key constraints:

```text
CUSTOMER_PROFILE (CUSTOMER_ID PK)
       └── ACCOUNT (ACCOUNT_ID PK, CUSTOMER_ID FK)
               └── SERVICE (SERVICE_ID PK, ACCOUNT_ID FK)
```

### 5. Oracle Views

| View | Purpose |
|---|---|
| VW_CUSTOMER_PROFILE | Clean profile view, active records only |
| VW_ACCOUNT_PROFILE | Account joined with profile |
| VW_SERVICE_ACCOUNT | Service joined with account |
| VW_CRM_FULL_PROFILE | Full 360° view across all three entities |

### 6. MongoDB CRM Collections

`oracle_to_mongodb.py` reads each view and builds document-oriented CRM structures:

| Collection | Source View | Key Field |
|---|---|---|
| crm_profiles | VW_CUSTOMER_PROFILE | customerId |
| crm_accounts | VW_ACCOUNT_PROFILE | accountId |
| crm_services | VW_SERVICE_ACCOUNT | serviceId |
| crm_full_360 | VW_CRM_FULL_PROFILE | customerId (nested accounts+services) |

All loads use `UpdateOne + upsert=True` for idempotent re-runs.

---

## Sample MongoDB Documents

### crm_profiles

```json
{
  "customerId": 1001,
  "fullName": "Himanshu Yadav",
  "email": "himanshu.yadav@email.com",
  "mobileNo": "9876543210",
  "address": {
    "city": "Bangalore",
    "state": "Karnataka",
    "pincode": "560001"
  },
  "status": "ACTIVE"
}
```

### crm_accounts

```json
{
  "accountId": 2001,
  "customerId": 1001,
  "accountType": "Prepaid",
  "billCycle": "Monthly",
  "accountStatus": "Active",
  "creditLimit": 500.0
}
```

### crm_services

```json
{
  "serviceId": 3001,
  "accountId": 2001,
  "serviceNumber": "9876543210",
  "serviceStatus": "Active",
  "plan": {
    "planName": "Basic Prepaid",
    "planType": "Prepaid",
    "dataLimitGb": 1,
    "voiceMinutes": "100",
    "smsLimit": "100"
  },
  "activationDate": "2025-01-01"
}
```

### crm_full_360

```json
{
  "customerId": 1001,
  "fullName": "Himanshu Yadav",
  "mobileNo": "9876543210",
  "accounts": [
    {
      "accountId": 2001,
      "accountType": "Prepaid",
      "services": [
        {
          "serviceId": 3001,
          "serviceNumber": "9876543210",
          "planName": "Basic Prepaid"
        }
      ]
    }
  ]
}
```

---

## How To Run

### Prerequisites

```bash
pip install -r requirements.txt
```

Update `configs/db_config.json` with your Oracle and MongoDB connection details.

### Step 1 — Create Oracle Tables

```sql
-- Run in SQL*Plus or SQL Developer
@sql/staging_tables.sql
@sql/target_tables.sql
```

### Step 2 — Compile PL/SQL Packages

```sql
@sql/packages.sql
```

Or compile individually:

```sql
@procedures/mig_profile_pkg.sql
@procedures/mig_account_pkg.sql
@procedures/mig_service_pkg.sql
```

### Step 3 — Create Oracle Views

```sql
@sql/views.sql
```

### Step 4 — Load Flat Files into Staging

```bash
python python/load_flatfile_to_staging.py
```

### Step 5 — Run Python Validation

```bash
python python/data_validation.py
```

### Step 6 — Execute PL/SQL Migration Packages

```sql
BEGIN
    MIG_PROFILE_PKG.LOAD_CUSTOMER_PROFILE('PROFILE_20250101');
END;
/

BEGIN
    MIG_ACCOUNT_PKG.LOAD_ACCOUNT('ACCOUNT_20250101');
END;
/

BEGIN
    MIG_SERVICE_PKG.LOAD_SERVICE('SERVICE_20250101');
END;
/
```

### Step 7 — Load MongoDB CRM Collections

```bash
python python/oracle_to_mongodb.py
```

### Step 8 — Validate MongoDB Data

```bash
python python/mongodb_compare.py
```

---

## Logging

All Python scripts write structured logs to the `logs/` directory:

| Log File | Script |
|---|---|
| logs/load_flatfile.log | load_flatfile_to_staging.py |
| logs/data_validation.log | data_validation.py |
| logs/oracle_to_mongodb.log | oracle_to_mongodb.py |
| logs/mongodb_compare.log | mongodb_compare.py |

Oracle-side logging goes to `MIG_VALIDATION_LOG` and `MIG_RUN_LOG` tables.

---

## Future Enhancements

- CDC-based incremental migration
- Apache Airflow orchestration
- AWS S3 source file ingestion
- Parallel migration using Oracle parallel hints
- Automated retry framework for failed records
- Monitoring dashboard (Grafana / Superset)
- Delta Lake integration for historical snapshots

---

## Author

**Himanshu Yadav**
Data Engineer — Oracle PL/SQL · MongoDB · Python ETL · Telecom CRM Migration
