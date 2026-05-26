# Telecom CRM Data Migration Platform

Python | Oracle PL/SQL | MongoDB | ETL | Data Migration

---

## Overview

End-to-end telecom CRM data migration platform that migrates customer, account, and service data from legacy flat files into Oracle and MongoDB systems.

The platform includes:
- Data ingestion
- Validation framework
- PL/SQL transformation layer
- CRM JSON generation
- MongoDB loading
- Reconciliation process

---

## Architecture

```text
Flat Files → Oracle Staging → Validation → PL/SQL Transformation → Oracle Views → MongoDB CRM Collections
```

---

## Tech Stack

- Python
- Oracle PL/SQL
- Oracle Database
- MongoDB
- Pandas
- cx_Oracle
- PyMongo

---

## Key Features

- End-to-End ETL Pipeline
- Telecom CRM Data Migration
- Validation & Reconciliation Framework
- Oracle PL/SQL Transformation Packages
- MongoDB CRM JSON Generation
- Idempotent Data Loads
- Batch Processing

---

## Migration Flow

1. Load flat files into Oracle staging tables
2. Validate source data using Python validation framework
3. Transform and load data using PL/SQL packages
4. Create Oracle views for CRM-ready datasets
5. Generate nested CRM JSON documents
6. Load data into MongoDB collections
7. Perform reconciliation and validation

---

## Repository Structure

```text
telecom-crm-migration-platform/
│
├── python/
├── procedures/
├── sql/
├── configs/
├── source_files/
├── docs/
├── README.md
└── requirements.txt
```

---

## Future Enhancements

- CDC-based Incremental Migration
- Apache Airflow Orchestration
- AWS S3 Integration
- Automated Monitoring Dashboard

---

## Author

Himanshu Yadav  
Data Engineer | Oracle PL/SQL | MongoDB | Python ETL
