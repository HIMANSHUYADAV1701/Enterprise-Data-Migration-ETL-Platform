"""
=============================================================
FILE   : data_validation.py
PURPOSE: Python-side validation framework for Oracle staging tables
         Runs after flat-file load, before PL/SQL packages
         Checks: null, duplicate, mandatory, referential, count recon
AUTHOR : Himanshu Yadav
=============================================================
"""

import os
import json
import logging
import cx_Oracle
from datetime import datetime

# ─── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("logs/data_validation.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

# ─── Config ───────────────────────────────────────────────────
BASE_DIR    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_PATH = os.path.join(BASE_DIR, "configs", "db_config.json")

with open(CONFIG_PATH) as f:
    config = json.load(f)

ORA_CFG = config["oracle"]
BATCH   = config["batch"]


# ─── Oracle connection ────────────────────────────────────────
def get_oracle_conn():
    dsn = cx_Oracle.makedsn(
        ORA_CFG["host"], ORA_CFG["port"], service_name=ORA_CFG["service_name"]
    )
    return cx_Oracle.connect(
        user=ORA_CFG["username"], password=ORA_CFG["password"], dsn=dsn
    )


# ─── Validation result tracker ───────────────────────────────
class ValidationResult:
    def __init__(self):
        self.results = []

    def add(self, table, check_type, status, count, message):
        self.results.append({
            "table": table,
            "check": check_type,
            "status": status,
            "count": count,
            "message": message,
        })
        icon = "✅" if status == "PASS" else "❌"
        logger.info(f"{icon} [{table}] {check_type}: {message} | Count: {count}")

    def summary(self):
        total = len(self.results)
        passed = sum(1 for r in self.results if r["status"] == "PASS")
        failed = total - passed
        logger.info("=" * 60)
        logger.info(f"Validation Summary: {passed}/{total} checks passed | {failed} failed")
        logger.info("=" * 60)
        if failed > 0:
            logger.warning("FAILED CHECKS:")
            for r in self.results:
                if r["status"] == "FAIL":
                    logger.warning(f"  ❌ [{r['table']}] {r['check']}: {r['message']}")
        return failed == 0


vr = ValidationResult()


# ─── Generic helpers ─────────────────────────────────────────
def fetch_one(cursor, sql, params=None):
    cursor.execute(sql, params or [])
    row = cursor.fetchone()
    return row[0] if row else 0


def log_to_oracle(cursor, conn, table, validation_type, batch_id, status, message, record_id=None):
    try:
        cursor.execute(
            """INSERT INTO MIG_VALIDATION_LOG
               (BATCH_ID, TABLE_NAME, VALIDATION_TYPE, RECORD_ID, STATUS, MESSAGE)
               VALUES (:1, :2, :3, :4, :5, :6)""",
            [batch_id, table, validation_type, record_id, status, message],
        )
        conn.commit()
    except Exception as e:
        logger.warning(f"Could not write to MIG_VALIDATION_LOG: {e}")


# ─── Null check ───────────────────────────────────────────────
def check_null(cursor, conn, table, column, batch_id):
    count = fetch_one(
        cursor,
        f"SELECT COUNT(*) FROM {table} WHERE {column} IS NULL AND BATCH_ID = :1",
        [batch_id],
    )
    status = "PASS" if count == 0 else "FAIL"
    msg = f"{column} null count = {count}"
    vr.add(table, f"NULL_CHECK:{column}", status, count, msg)
    log_to_oracle(cursor, conn, table, f"NULL_CHECK:{column}", batch_id, status, msg)


# ─── Duplicate check ─────────────────────────────────────────
def check_duplicate(cursor, conn, table, key_column, batch_id):
    count = fetch_one(
        cursor,
        f"""SELECT COUNT(*) FROM (
                SELECT {key_column} FROM {table}
                WHERE  BATCH_ID = :1
                GROUP BY {key_column} HAVING COUNT(*) > 1
            )""",
        [batch_id],
    )
    status = "PASS" if count == 0 else "FAIL"
    msg = f"Duplicate {key_column} count = {count}"
    vr.add(table, f"DUPLICATE_CHECK:{key_column}", status, count, msg)
    log_to_oracle(cursor, conn, table, f"DUPLICATE_CHECK:{key_column}", batch_id, status, msg)


# ─── Row count recon ─────────────────────────────────────────
def check_row_count(cursor, conn, table, batch_id, expected_count):
    actual = fetch_one(
        cursor,
        f"SELECT COUNT(*) FROM {table} WHERE BATCH_ID = :1",
        [batch_id],
    )
    status = "PASS" if actual == expected_count else "FAIL"
    msg = f"Expected={expected_count} | Actual={actual}"
    vr.add(table, "ROW_COUNT_CHECK", status, actual, msg)
    log_to_oracle(cursor, conn, table, "ROW_COUNT_CHECK", batch_id, status, msg)


# ─── Valid value check ───────────────────────────────────────
def check_valid_values(cursor, conn, table, column, valid_values, batch_id):
    placeholders = ",".join([f"'{v}'" for v in valid_values])
    count = fetch_one(
        cursor,
        f"""SELECT COUNT(*) FROM {table}
            WHERE {column} IS NOT NULL
            AND   {column} NOT IN ({placeholders})
            AND   BATCH_ID = :1""",
        [batch_id],
    )
    status = "PASS" if count == 0 else "FAIL"
    msg = f"{column} invalid values count = {count}"
    vr.add(table, f"VALID_VALUE:{column}", status, count, msg)
    log_to_oracle(cursor, conn, table, f"VALID_VALUE:{column}", batch_id, status, msg)


# ─── Referential integrity check ─────────────────────────────
def check_referential(cursor, conn, child_table, child_col, parent_table, parent_col, batch_id):
    count = fetch_one(
        cursor,
        f"""SELECT COUNT(*) FROM {child_table} c
            WHERE  c.BATCH_ID = :1
            AND    c.{child_col} IS NOT NULL
            AND    NOT EXISTS (
                SELECT 1 FROM {parent_table} p
                WHERE  TO_CHAR(p.{parent_col}) = c.{child_col}
            )""",
        [batch_id],
    )
    status = "PASS" if count == 0 else "FAIL"
    msg = f"{child_table}.{child_col} → {parent_table}.{parent_col} orphan count = {count}"
    vr.add(child_table, f"REF_INTEGRITY:{child_col}", status, count, msg)
    log_to_oracle(cursor, conn, child_table, f"REF_INTEGRITY:{child_col}", batch_id, status, msg)


# ─── Invalid staging count ───────────────────────────────────
def check_invalid_count(cursor, conn, table, batch_id):
    count = fetch_one(
        cursor,
        f"SELECT COUNT(*) FROM {table} WHERE STG_STATUS = 'INVALID' AND BATCH_ID = :1",
        [batch_id],
    )
    status = "PASS" if count == 0 else "FAIL"
    msg = f"INVALID records in staging = {count}"
    vr.add(table, "INVALID_RECORD_CHECK", status, count, msg)
    log_to_oracle(cursor, conn, table, "INVALID_RECORD_CHECK", batch_id, status, msg)


# ─── Profile validations ─────────────────────────────────────
def validate_profile(cursor, conn):
    logger.info("─" * 40)
    logger.info("Validating: STG_CUSTOMER_PROFILE")
    bid = BATCH["profile_batch_id"]

    check_null(cursor, conn, "STG_CUSTOMER_PROFILE", "CUSTOMER_ID",  bid)
    check_null(cursor, conn, "STG_CUSTOMER_PROFILE", "FIRST_NAME",   bid)
    check_null(cursor, conn, "STG_CUSTOMER_PROFILE", "LAST_NAME",    bid)
    check_null(cursor, conn, "STG_CUSTOMER_PROFILE", "MOBILE_NO",    bid)

    check_duplicate(cursor, conn, "STG_CUSTOMER_PROFILE", "CUSTOMER_ID", bid)

    check_valid_values(cursor, conn, "STG_CUSTOMER_PROFILE", "GENDER",
                       ["M", "F", "O"], bid)

    # Mobile number length = 10
    count = fetch_one(
        cursor,
        """SELECT COUNT(*) FROM STG_CUSTOMER_PROFILE
           WHERE MOBILE_NO IS NOT NULL AND LENGTH(MOBILE_NO) != 10
           AND BATCH_ID = :1""",
        [bid],
    )
    status = "PASS" if count == 0 else "FAIL"
    vr.add("STG_CUSTOMER_PROFILE", "MOBILE_NO_LENGTH", status, count,
           f"Invalid mobile length count = {count}")

    # Row count reconciliation — source file
    import pandas as pd
    source_count = len(pd.read_csv(
        os.path.join(BASE_DIR, config["source_files"]["profile_file"]), dtype=str
    ))
    check_row_count(cursor, conn, "STG_CUSTOMER_PROFILE", bid, source_count)


# ─── Account validations ─────────────────────────────────────
def validate_account(cursor, conn):
    logger.info("─" * 40)
    logger.info("Validating: STG_ACCOUNT")
    bid = BATCH["account_batch_id"]

    check_null(cursor, conn, "STG_ACCOUNT", "ACCOUNT_ID",  bid)
    check_null(cursor, conn, "STG_ACCOUNT", "CUSTOMER_ID", bid)

    check_duplicate(cursor, conn, "STG_ACCOUNT", "ACCOUNT_ID", bid)

    check_valid_values(cursor, conn, "STG_ACCOUNT", "ACCOUNT_TYPE",
                       ["Prepaid", "Postpaid", "Hybrid"], bid)
    check_valid_values(cursor, conn, "STG_ACCOUNT", "ACCOUNT_STATUS",
                       ["Active", "Inactive", "Suspended", "Closed"], bid)

    # Referential check: CUSTOMER_ID must be in STG_CUSTOMER_PROFILE of profile batch
    check_referential(cursor, conn,
                      "STG_ACCOUNT", "CUSTOMER_ID",
                      "CUSTOMER_PROFILE", "CUSTOMER_ID",
                      bid)

    import pandas as pd
    source_count = len(pd.read_csv(
        os.path.join(BASE_DIR, config["source_files"]["account_file"]), dtype=str
    ))
    check_row_count(cursor, conn, "STG_ACCOUNT", bid, source_count)


# ─── Service validations ─────────────────────────────────────
def validate_service(cursor, conn):
    logger.info("─" * 40)
    logger.info("Validating: STG_SERVICE")
    bid = BATCH["service_batch_id"]

    check_null(cursor, conn, "STG_SERVICE", "SERVICE_ID",     bid)
    check_null(cursor, conn, "STG_SERVICE", "ACCOUNT_ID",     bid)
    check_null(cursor, conn, "STG_SERVICE", "SERVICE_NUMBER", bid)

    check_duplicate(cursor, conn, "STG_SERVICE", "SERVICE_ID", bid)

    check_valid_values(cursor, conn, "STG_SERVICE", "SERVICE_STATUS",
                       ["Active", "Inactive", "Suspended", "Terminated"], bid)

    check_referential(cursor, conn,
                      "STG_SERVICE", "ACCOUNT_ID",
                      "ACCOUNT", "ACCOUNT_ID",
                      bid)

    import pandas as pd
    source_count = len(pd.read_csv(
        os.path.join(BASE_DIR, config["source_files"]["service_file"]), dtype=str
    ))
    check_row_count(cursor, conn, "STG_SERVICE", bid, source_count)


# ─── Target post-load checks ─────────────────────────────────
def validate_target_counts(cursor, conn):
    logger.info("─" * 40)
    logger.info("Post-Load Target Table Count Checks")

    for table, bid_key in [
        ("CUSTOMER_PROFILE", "profile_batch_id"),
        ("ACCOUNT",          "account_batch_id"),
        ("SERVICE",          "service_batch_id"),
    ]:
        bid = BATCH[bid_key]
        count = fetch_one(
            cursor,
            f"SELECT COUNT(*) FROM {table} WHERE MIG_BATCH_ID = :1",
            [bid],
        )
        msg = f"Target {table} row count = {count}"
        vr.add(table, "TARGET_COUNT_CHECK", "INFO", count, msg)


# ─── Main ─────────────────────────────────────────────────────
def main():
    os.makedirs("logs", exist_ok=True)
    logger.info("=" * 60)
    logger.info("Data Validation Framework | Started")
    logger.info("=" * 60)

    conn   = get_oracle_conn()
    cursor = conn.cursor()

    try:
        validate_profile(cursor, conn)
        validate_account(cursor, conn)
        validate_service(cursor, conn)
        validate_target_counts(cursor, conn)

        all_passed = vr.summary()
        if not all_passed:
            logger.warning("Some validations FAILED. Review logs before proceeding.")
        else:
            logger.info("All validations PASSED. Ready for PL/SQL transformation.")

    except Exception as e:
        logger.error(f"FATAL ERROR: {e}", exc_info=True)
        raise

    finally:
        cursor.close()
        conn.close()
        logger.info("Oracle connection closed.")


if __name__ == "__main__":
    main()
