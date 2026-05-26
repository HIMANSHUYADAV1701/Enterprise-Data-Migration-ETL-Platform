"""
=============================================================
FILE   : load_flatfile_to_staging.py
PURPOSE: Load CSV flat files into Oracle staging tables
         - STG_CUSTOMER_PROFILE
         - STG_ACCOUNT
         - STG_SERVICE
AUTHOR : Himanshu Yadav
=============================================================
"""

import os
import json
import logging
import pandas as pd
import cx_Oracle
from datetime import datetime

# ─── Logging setup ────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("logs/load_flatfile.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

# ─── Load config ──────────────────────────────────────────────
BASE_DIR    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(BASE_DIR, "configs", "db_config.json")

with open(CONFIG_PATH) as f:
    config = json.load(f)

ORA_CFG  = config["oracle"]
BATCH    = config["batch"]
SRC      = config["source_files"]


# ─── Oracle connection helper ─────────────────────────────────
def get_oracle_conn():
    dsn = cx_Oracle.makedsn(
        ORA_CFG["host"],
        ORA_CFG["port"],
        service_name=ORA_CFG["service_name"],
    )
    conn = cx_Oracle.connect(
        user=ORA_CFG["username"],
        password=ORA_CFG["password"],
        dsn=dsn,
    )
    logger.info("Oracle connection established.")
    return conn


# ─── Generic CSV reader ───────────────────────────────────────
def read_csv(file_path: str) -> pd.DataFrame:
    full_path = os.path.join(BASE_DIR, file_path)
    logger.info(f"Reading file: {full_path}")
    df = pd.read_csv(full_path, dtype=str)
    df = df.where(pd.notnull(df), None)   # Replace NaN with None for Oracle
    logger.info(f"Rows loaded from file: {len(df)}")
    return df


# ─── Load profile staging ─────────────────────────────────────
def load_profile_staging(conn, df: pd.DataFrame, batch_id: str):
    cursor = conn.cursor()
    source_file = SRC["profile_file"]

    sql = """
        INSERT INTO STG_CUSTOMER_PROFILE (
            CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL,
            MOBILE_NO, DOB, GENDER, ADDRESS,
            CITY, STATE, PINCODE, CREATED_DATE,
            SOURCE_FILE, BATCH_ID
        ) VALUES (
            :1, :2, :3, :4,
            :5, :6, :7, :8,
            :9, :10, :11, :12,
            :13, :14
        )
    """

    rows = []
    for _, row in df.iterrows():
        rows.append((
            row.get("CUSTOMER_ID"),
            row.get("FIRST_NAME"),
            row.get("LAST_NAME"),
            row.get("EMAIL"),
            row.get("MOBILE_NO"),
            row.get("DOB"),
            row.get("GENDER"),
            row.get("ADDRESS"),
            row.get("CITY"),
            row.get("STATE"),
            row.get("PINCODE"),
            row.get("CREATED_DATE"),
            source_file,
            batch_id,
        ))

    cursor.executemany(sql, rows)
    conn.commit()
    logger.info(f"Profile staging loaded: {len(rows)} rows | Batch: {batch_id}")
    cursor.close()


# ─── Load account staging ─────────────────────────────────────
def load_account_staging(conn, df: pd.DataFrame, batch_id: str):
    cursor = conn.cursor()
    source_file = SRC["account_file"]

    sql = """
        INSERT INTO STG_ACCOUNT (
            ACCOUNT_ID, CUSTOMER_ID, ACCOUNT_TYPE, BILL_CYCLE,
            ACCOUNT_STATUS, CREDIT_LIMIT, BILLING_ADDRESS, BILLING_CITY,
            BILLING_STATE, BILLING_PINCODE, ACCOUNT_OPEN_DATE,
            SOURCE_FILE, BATCH_ID
        ) VALUES (
            :1, :2, :3, :4,
            :5, :6, :7, :8,
            :9, :10, :11,
            :12, :13
        )
    """

    rows = []
    for _, row in df.iterrows():
        rows.append((
            row.get("ACCOUNT_ID"),
            row.get("CUSTOMER_ID"),
            row.get("ACCOUNT_TYPE"),
            row.get("BILL_CYCLE"),
            row.get("ACCOUNT_STATUS"),
            row.get("CREDIT_LIMIT"),
            row.get("BILLING_ADDRESS"),
            row.get("BILLING_CITY"),
            row.get("BILLING_STATE"),
            row.get("BILLING_PINCODE"),
            row.get("ACCOUNT_OPEN_DATE"),
            source_file,
            batch_id,
        ))

    cursor.executemany(sql, rows)
    conn.commit()
    logger.info(f"Account staging loaded: {len(rows)} rows | Batch: {batch_id}")
    cursor.close()


# ─── Load service staging ─────────────────────────────────────
def load_service_staging(conn, df: pd.DataFrame, batch_id: str):
    cursor = conn.cursor()
    source_file = SRC["service_file"]

    sql = """
        INSERT INTO STG_SERVICE (
            SERVICE_ID, ACCOUNT_ID, SERVICE_NUMBER, SERVICE_TYPE,
            SERVICE_STATUS, PLAN_NAME, PLAN_TYPE, DATA_LIMIT_GB,
            VOICE_MINUTES, SMS_LIMIT, ACTIVATION_DATE, DEACTIVATION_DATE,
            SOURCE_FILE, BATCH_ID
        ) VALUES (
            :1, :2, :3, :4,
            :5, :6, :7, :8,
            :9, :10, :11, :12,
            :13, :14
        )
    """

    rows = []
    for _, row in df.iterrows():
        rows.append((
            row.get("SERVICE_ID"),
            row.get("ACCOUNT_ID"),
            row.get("SERVICE_NUMBER"),
            row.get("SERVICE_TYPE"),
            row.get("SERVICE_STATUS"),
            row.get("PLAN_NAME"),
            row.get("PLAN_TYPE"),
            row.get("DATA_LIMIT_GB"),
            row.get("VOICE_MINUTES"),
            row.get("SMS_LIMIT"),
            row.get("ACTIVATION_DATE"),
            row.get("DEACTIVATION_DATE"),
            source_file,
            batch_id,
        ))

    cursor.executemany(sql, rows)
    conn.commit()
    logger.info(f"Service staging loaded: {len(rows)} rows | Batch: {batch_id}")
    cursor.close()


# ─── Reconciliation check ─────────────────────────────────────
def reconcile_load(conn, stg_table: str, batch_id: str, source_count: int):
    cursor = conn.cursor()
    cursor.execute(
        f"SELECT COUNT(*) FROM {stg_table} WHERE BATCH_ID = :1",
        [batch_id],
    )
    stg_count = cursor.fetchone()[0]
    cursor.close()

    status = "PASS" if stg_count == source_count else "FAIL"
    logger.info(
        f"Reconciliation [{stg_table}] | Source: {source_count} | Staged: {stg_count} | {status}"
    )
    return status


# ─── Main ─────────────────────────────────────────────────────
def main():
    os.makedirs("logs", exist_ok=True)
    logger.info("=" * 60)
    logger.info("Flat File → Oracle Staging | Migration Started")
    logger.info("=" * 60)

    conn = get_oracle_conn()

    try:
        # ── Profile ──
        logger.info("--- Loading Customer Profile ---")
        profile_df  = read_csv(SRC["profile_file"])
        profile_bid = BATCH["profile_batch_id"]
        load_profile_staging(conn, profile_df, profile_bid)
        reconcile_load(conn, "STG_CUSTOMER_PROFILE", profile_bid, len(profile_df))

        # ── Account ──
        logger.info("--- Loading Account ---")
        account_df  = read_csv(SRC["account_file"])
        account_bid = BATCH["account_batch_id"]
        load_account_staging(conn, account_df, account_bid)
        reconcile_load(conn, "STG_ACCOUNT", account_bid, len(account_df))

        # ── Service ──
        logger.info("--- Loading Service ---")
        service_df  = read_csv(SRC["service_file"])
        service_bid = BATCH["service_batch_id"]
        load_service_staging(conn, service_df, service_bid)
        reconcile_load(conn, "STG_SERVICE", service_bid, len(service_df))

        logger.info("=" * 60)
        logger.info("Flat File → Oracle Staging | Completed Successfully")
        logger.info("=" * 60)

    except Exception as e:
        logger.error(f"FATAL ERROR: {e}", exc_info=True)
        raise

    finally:
        conn.close()
        logger.info("Oracle connection closed.")


if __name__ == "__main__":
    main()
