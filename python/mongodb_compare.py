"""
=============================================================
FILE   : mongodb_compare.py
PURPOSE: Reconcile Oracle target tables vs MongoDB collections
         Checks:
           - Row counts match
           - Key field values match for sampled records
           - No orphan documents in MongoDB
AUTHOR : Himanshu Yadav
=============================================================
"""

import os
import json
import logging
import cx_Oracle
from pymongo import MongoClient

# ─── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("logs/mongodb_compare.log"),
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
MDB_CFG = config["mongodb"]


def get_oracle_conn():
    dsn = cx_Oracle.makedsn(
        ORA_CFG["host"], ORA_CFG["port"], service_name=ORA_CFG["service_name"]
    )
    return cx_Oracle.connect(
        user=ORA_CFG["username"], password=ORA_CFG["password"], dsn=dsn
    )


def get_mongo_client():
    if MDB_CFG.get("username"):
        uri = (
            f"mongodb://{MDB_CFG['username']}:{MDB_CFG['password']}"
            f"@{MDB_CFG['host']}:{MDB_CFG['port']}/{MDB_CFG['database']}"
            f"?authSource={MDB_CFG['auth_source']}"
        )
    else:
        uri = f"mongodb://{MDB_CFG['host']}:{MDB_CFG['port']}"
    return MongoClient(uri)


# ─── Reconciliation results ───────────────────────────────────
class ReconResult:
    def __init__(self):
        self.checks = []

    def add(self, name, oracle_val, mongo_val, match):
        status = "✅ MATCH" if match else "❌ MISMATCH"
        self.checks.append({
            "name": name, "oracle": oracle_val, "mongo": mongo_val, "match": match
        })
        logger.info(f"{status} | {name} | Oracle={oracle_val} | MongoDB={mongo_val}")

    def summary(self):
        total   = len(self.checks)
        matched = sum(1 for c in self.checks if c["match"])
        failed  = total - matched
        logger.info("=" * 60)
        logger.info(f"Reconciliation Summary: {matched}/{total} checks matched | {failed} mismatches")
        if failed:
            logger.warning("MISMATCHES:")
            for c in self.checks:
                if not c["match"]:
                    logger.warning(f"  ❌ {c['name']}: Oracle={c['oracle']} | MongoDB={c['mongo']}")
        logger.info("=" * 60)
        return failed == 0


rr = ReconResult()


# ─── Count recon ─────────────────────────────────────────────
def count_recon(ora_cursor, mongo_db):
    logger.info("─" * 40)
    logger.info("Count Reconciliation")

    checks = [
        ("CUSTOMER_PROFILE",  "VW_CUSTOMER_PROFILE", "crm_profiles",  "customerId"),
        ("ACCOUNT",           "VW_ACCOUNT_PROFILE",  "crm_accounts",  "accountId"),
        ("SERVICE",           "VW_SERVICE_ACCOUNT",  "crm_services",  "serviceId"),
    ]

    for ora_table, ora_view, mongo_col, _ in checks:
        # Oracle active count
        ora_cursor.execute(f"SELECT COUNT(*) FROM {ora_view}")
        ora_count = ora_cursor.fetchone()[0]

        # MongoDB count
        mdb_count = mongo_db[mongo_col].count_documents({})

        rr.add(f"COUNT | {ora_table} vs {mongo_col}", ora_count, mdb_count,
               ora_count == mdb_count)


# ─── Field-level spot check ───────────────────────────────────
def field_recon_profiles(ora_cursor, mongo_db):
    logger.info("─" * 40)
    logger.info("Field Reconciliation: Profiles")

    ora_cursor.execute(
        "SELECT CUSTOMER_ID, FULL_NAME, MOBILE_NO FROM VW_CUSTOMER_PROFILE"
    )
    for row in ora_cursor.fetchall():
        cid, full_name, mobile = row
        doc = mongo_db["crm_profiles"].find_one({"customerId": cid})

        if doc is None:
            rr.add(f"PROFILE_EXISTS | customerId={cid}", "exists", "NOT FOUND", False)
            continue

        rr.add(f"PROFILE_FULLNAME | customerId={cid}",
               full_name, doc.get("fullName"), full_name == doc.get("fullName"))
        rr.add(f"PROFILE_MOBILE   | customerId={cid}",
               mobile, doc.get("mobileNo"), mobile == doc.get("mobileNo"))


def field_recon_accounts(ora_cursor, mongo_db):
    logger.info("─" * 40)
    logger.info("Field Reconciliation: Accounts")

    ora_cursor.execute(
        "SELECT ACCOUNT_ID, ACCOUNT_TYPE, ACCOUNT_STATUS FROM VW_ACCOUNT_PROFILE"
    )
    for row in ora_cursor.fetchall():
        aid, acct_type, acct_status = row
        doc = mongo_db["crm_accounts"].find_one({"accountId": aid})

        if doc is None:
            rr.add(f"ACCOUNT_EXISTS | accountId={aid}", "exists", "NOT FOUND", False)
            continue

        rr.add(f"ACCOUNT_TYPE   | accountId={aid}",
               acct_type, doc.get("accountType"), acct_type == doc.get("accountType"))
        rr.add(f"ACCOUNT_STATUS | accountId={aid}",
               acct_status, doc.get("accountStatus"), acct_status == doc.get("accountStatus"))


def field_recon_services(ora_cursor, mongo_db):
    logger.info("─" * 40)
    logger.info("Field Reconciliation: Services")

    ora_cursor.execute(
        "SELECT SERVICE_ID, SERVICE_NUMBER, SERVICE_STATUS FROM VW_SERVICE_ACCOUNT"
    )
    for row in ora_cursor.fetchall():
        sid, svc_num, svc_status = row
        doc = mongo_db["crm_services"].find_one({"serviceId": sid})

        if doc is None:
            rr.add(f"SERVICE_EXISTS | serviceId={sid}", "exists", "NOT FOUND", False)
            continue

        rr.add(f"SERVICE_NUMBER | serviceId={sid}",
               svc_num, doc.get("serviceNumber"), svc_num == doc.get("serviceNumber"))
        rr.add(f"SERVICE_STATUS | serviceId={sid}",
               svc_status, doc.get("serviceStatus"), svc_status == doc.get("serviceStatus"))


# ─── Orphan check ─────────────────────────────────────────────
def orphan_check(ora_cursor, mongo_db):
    logger.info("─" * 40)
    logger.info("Orphan Check: MongoDB documents not in Oracle")

    # Profile orphans
    ora_cursor.execute("SELECT CUSTOMER_ID FROM VW_CUSTOMER_PROFILE")
    oracle_cids = {r[0] for r in ora_cursor.fetchall()}
    mongo_cids  = {d["customerId"] for d in mongo_db["crm_profiles"].find({}, {"customerId": 1})}
    orphans     = mongo_cids - oracle_cids
    rr.add("ORPHAN_CHECK | crm_profiles", 0, len(orphans), len(orphans) == 0)

    # Account orphans
    ora_cursor.execute("SELECT ACCOUNT_ID FROM VW_ACCOUNT_PROFILE")
    oracle_aids = {r[0] for r in ora_cursor.fetchall()}
    mongo_aids  = {d["accountId"] for d in mongo_db["crm_accounts"].find({}, {"accountId": 1})}
    orphans     = mongo_aids - oracle_aids
    rr.add("ORPHAN_CHECK | crm_accounts", 0, len(orphans), len(orphans) == 0)

    # Service orphans
    ora_cursor.execute("SELECT SERVICE_ID FROM VW_SERVICE_ACCOUNT")
    oracle_sids = {r[0] for r in ora_cursor.fetchall()}
    mongo_sids  = {d["serviceId"] for d in mongo_db["crm_services"].find({}, {"serviceId": 1})}
    orphans     = mongo_sids - oracle_sids
    rr.add("ORPHAN_CHECK | crm_services", 0, len(orphans), len(orphans) == 0)


# ─── Print sample docs ───────────────────────────────────────
def print_sample_documents(mongo_db):
    logger.info("─" * 40)
    logger.info("Sample MongoDB Documents")

    for col in ["crm_profiles", "crm_accounts", "crm_services", "crm_full_360"]:
        doc = mongo_db[col].find_one({}, {"_id": 0})
        if doc:
            logger.info(f"\n[{col}] sample:\n{json.dumps(doc, default=str, indent=2)}")
        else:
            logger.warning(f"[{col}] — collection is empty.")


# ─── Main ─────────────────────────────────────────────────────
def main():
    os.makedirs("logs", exist_ok=True)
    logger.info("=" * 60)
    logger.info("MongoDB Reconciliation | Started")
    logger.info("=" * 60)

    ora_conn     = get_oracle_conn()
    ora_cursor   = ora_conn.cursor()
    mongo_client = get_mongo_client()
    mongo_db     = mongo_client[MDB_CFG["database"]]

    try:
        count_recon(ora_cursor, mongo_db)
        field_recon_profiles(ora_cursor, mongo_db)
        field_recon_accounts(ora_cursor, mongo_db)
        field_recon_services(ora_cursor, mongo_db)
        orphan_check(ora_cursor, mongo_db)
        print_sample_documents(mongo_db)

        all_ok = rr.summary()
        if not all_ok:
            logger.warning("Reconciliation found mismatches. Review logs.")
        else:
            logger.info("Full reconciliation PASSED. Oracle ↔ MongoDB data is consistent.")

    except Exception as e:
        logger.error(f"FATAL ERROR: {e}", exc_info=True)
        raise
    finally:
        ora_cursor.close()
        ora_conn.close()
        mongo_client.close()
        logger.info("Connections closed.")


if __name__ == "__main__":
    main()
