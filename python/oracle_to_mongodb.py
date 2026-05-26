"""
=============================================================
FILE   : oracle_to_mongodb.py
PURPOSE: Read Oracle views → Build CRM JSON documents → Load MongoDB
         Collections:
           - crm_profiles   (from VW_CUSTOMER_PROFILE)
           - crm_accounts   (from VW_ACCOUNT_PROFILE)
           - crm_services   (from VW_SERVICE_ACCOUNT)
           - crm_full_360   (from VW_CRM_FULL_PROFILE)
AUTHOR : Himanshu Yadav
=============================================================
"""

import os
import json
import logging
import cx_Oracle
from pymongo import MongoClient, UpdateOne
from pymongo.errors import BulkWriteError
from datetime import datetime

# ─── Logging ──────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler("logs/oracle_to_mongodb.log"),
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


# ─── Oracle connection ────────────────────────────────────────
def get_oracle_conn():
    dsn = cx_Oracle.makedsn(
        ORA_CFG["host"], ORA_CFG["port"], service_name=ORA_CFG["service_name"]
    )
    conn = cx_Oracle.connect(
        user=ORA_CFG["username"], password=ORA_CFG["password"], dsn=dsn
    )
    logger.info("Oracle connection established.")
    return conn


# ─── MongoDB connection ───────────────────────────────────────
def get_mongo_client():
    if MDB_CFG.get("username"):
        uri = (
            f"mongodb://{MDB_CFG['username']}:{MDB_CFG['password']}"
            f"@{MDB_CFG['host']}:{MDB_CFG['port']}/{MDB_CFG['database']}"
            f"?authSource={MDB_CFG['auth_source']}"
        )
    else:
        uri = f"mongodb://{MDB_CFG['host']}:{MDB_CFG['port']}"

    client = MongoClient(uri)
    logger.info("MongoDB connection established.")
    return client


# ─── Fetch Oracle rows as list of dicts ──────────────────────
def fetch_as_dicts(cursor, sql):
    cursor.execute(sql)
    columns = [col[0].lower() for col in cursor.description]
    rows = cursor.fetchall()
    return [dict(zip(columns, row)) for row in rows]


# ─── Load Profile collection ─────────────────────────────────
def load_profiles(ora_cursor, mongo_db):
    logger.info("--- Loading crm_profiles collection ---")

    sql = """
        SELECT
            PROFILE_ID,
            CUSTOMER_ID,
            FIRST_NAME,
            LAST_NAME,
            FULL_NAME,
            EMAIL,
            MOBILE_NO,
            DOB,
            GENDER,
            ADDRESS,
            CITY,
            STATE,
            PINCODE,
            CREATED_DATE,
            RECORD_STATUS
        FROM VW_CUSTOMER_PROFILE
    """
    rows = fetch_as_dicts(ora_cursor, sql)

    ops = []
    for r in rows:
        doc = {
            "profileId":    r["profile_id"],
            "customerId":   r["customer_id"],
            "firstName":    r["first_name"],
            "lastName":     r["last_name"],
            "fullName":     r["full_name"],
            "email":        r["email"],
            "mobileNo":     r["mobile_no"],
            "dob":          r["dob"],
            "gender":       r["gender"],
            "address": {
                "line1":   r["address"],
                "city":    r["city"],
                "state":   r["state"],
                "pincode": r["pincode"],
            },
            "createdDate":  r["created_date"],
            "status":       r["record_status"],
            "loadedAt":     datetime.utcnow().isoformat(),
        }
        ops.append(
            UpdateOne(
                {"customerId": doc["customerId"]},
                {"$set": doc},
                upsert=True,
            )
        )

    if ops:
        result = mongo_db["crm_profiles"].bulk_write(ops)
        logger.info(f"crm_profiles: upserted={result.upserted_count} modified={result.modified_count}")
    else:
        logger.warning("crm_profiles: no records found.")


# ─── Load Account collection ─────────────────────────────────
def load_accounts(ora_cursor, mongo_db):
    logger.info("--- Loading crm_accounts collection ---")

    sql = """
        SELECT
            ACCOUNT_ID,
            CUSTOMER_ID,
            FULL_NAME,
            MOBILE_NO,
            EMAIL,
            ACCOUNT_TYPE,
            BILL_CYCLE,
            ACCOUNT_STATUS,
            CREDIT_LIMIT,
            BILLING_CITY,
            BILLING_STATE,
            ACCOUNT_OPEN_DATE
        FROM VW_ACCOUNT_PROFILE
    """
    rows = fetch_as_dicts(ora_cursor, sql)

    ops = []
    for r in rows:
        doc = {
            "accountId":      r["account_id"],
            "customerId":     r["customer_id"],
            "customerName":   r["full_name"],
            "mobileNo":       r["mobile_no"],
            "email":          r["email"],
            "accountType":    r["account_type"],
            "billCycle":      r["bill_cycle"],
            "accountStatus":  r["account_status"],
            "creditLimit":    float(r["credit_limit"]) if r["credit_limit"] else None,
            "billingCity":    r["billing_city"],
            "billingState":   r["billing_state"],
            "accountOpenDate": r["account_open_date"],
            "loadedAt":       datetime.utcnow().isoformat(),
        }
        ops.append(
            UpdateOne(
                {"accountId": doc["accountId"]},
                {"$set": doc},
                upsert=True,
            )
        )

    if ops:
        result = mongo_db["crm_accounts"].bulk_write(ops)
        logger.info(f"crm_accounts: upserted={result.upserted_count} modified={result.modified_count}")
    else:
        logger.warning("crm_accounts: no records found.")


# ─── Load Service collection ─────────────────────────────────
def load_services(ora_cursor, mongo_db):
    logger.info("--- Loading crm_services collection ---")

    sql = """
        SELECT
            SERVICE_ID,
            ACCOUNT_ID,
            CUSTOMER_ID,
            SERVICE_NUMBER,
            SERVICE_TYPE,
            SERVICE_STATUS,
            PLAN_NAME,
            PLAN_TYPE,
            DATA_LIMIT_GB,
            VOICE_MINUTES,
            SMS_LIMIT,
            ACTIVATION_DATE,
            DEACTIVATION_DATE
        FROM VW_SERVICE_ACCOUNT
    """
    rows = fetch_as_dicts(ora_cursor, sql)

    ops = []
    for r in rows:
        doc = {
            "serviceId":        r["service_id"],
            "accountId":        r["account_id"],
            "customerId":       r["customer_id"],
            "serviceNumber":    r["service_number"],
            "serviceType":      r["service_type"],
            "serviceStatus":    r["service_status"],
            "plan": {
                "planName":     r["plan_name"],
                "planType":     r["plan_type"],
                "dataLimitGb":  r["data_limit_gb"],
                "voiceMinutes": r["voice_minutes"],
                "smsLimit":     r["sms_limit"],
            },
            "activationDate":   r["activation_date"],
            "deactivationDate": r["deactivation_date"],
            "loadedAt":         datetime.utcnow().isoformat(),
        }
        ops.append(
            UpdateOne(
                {"serviceId": doc["serviceId"]},
                {"$set": doc},
                upsert=True,
            )
        )

    if ops:
        result = mongo_db["crm_services"].bulk_write(ops)
        logger.info(f"crm_services: upserted={result.upserted_count} modified={result.modified_count}")
    else:
        logger.warning("crm_services: no records found.")


# ─── Load 360 CRM full view ──────────────────────────────────
def load_crm_360(ora_cursor, mongo_db):
    logger.info("--- Loading crm_full_360 collection ---")

    sql = """
        SELECT
            CUSTOMER_ID,
            FULL_NAME,
            EMAIL,
            MOBILE_NO,
            CITY,
            STATE,
            ACCOUNT_ID,
            ACCOUNT_TYPE,
            ACCOUNT_STATUS,
            BILL_CYCLE,
            SERVICE_ID,
            SERVICE_NUMBER,
            SERVICE_STATUS,
            PLAN_NAME,
            PLAN_TYPE,
            ACTIVATION_DATE
        FROM VW_CRM_FULL_PROFILE
    """
    rows = fetch_as_dicts(ora_cursor, sql)

    # Group by customer for 360 doc
    customers = {}
    for r in rows:
        cid = r["customer_id"]
        if cid not in customers:
            customers[cid] = {
                "customerId":  cid,
                "fullName":    r["full_name"],
                "email":       r["email"],
                "mobileNo":    r["mobile_no"],
                "city":        r["city"],
                "state":       r["state"],
                "accounts":    [],
            }
        # Find or create account entry
        acct = next((a for a in customers[cid]["accounts"]
                     if a["accountId"] == r["account_id"]), None)
        if acct is None:
            acct = {
                "accountId":     r["account_id"],
                "accountType":   r["account_type"],
                "accountStatus": r["account_status"],
                "billCycle":     r["bill_cycle"],
                "services":      [],
            }
            customers[cid]["accounts"].append(acct)

        acct["services"].append({
            "serviceId":      r["service_id"],
            "serviceNumber":  r["service_number"],
            "serviceStatus":  r["service_status"],
            "planName":       r["plan_name"],
            "planType":       r["plan_type"],
            "activationDate": r["activation_date"],
        })

    ops = []
    for cid, doc in customers.items():
        doc["loadedAt"] = datetime.utcnow().isoformat()
        ops.append(
            UpdateOne(
                {"customerId": cid},
                {"$set": doc},
                upsert=True,
            )
        )

    if ops:
        result = mongo_db["crm_full_360"].bulk_write(ops)
        logger.info(f"crm_full_360: upserted={result.upserted_count} modified={result.modified_count}")
    else:
        logger.warning("crm_full_360: no records found.")


# ─── Create MongoDB indexes ───────────────────────────────────
def create_indexes(mongo_db):
    logger.info("--- Creating MongoDB indexes ---")
    mongo_db["crm_profiles"].create_index("customerId",  unique=True)
    mongo_db["crm_accounts"].create_index("accountId",   unique=True)
    mongo_db["crm_accounts"].create_index("customerId")
    mongo_db["crm_services"].create_index("serviceId",   unique=True)
    mongo_db["crm_services"].create_index("accountId")
    mongo_db["crm_services"].create_index("serviceNumber")
    mongo_db["crm_full_360"].create_index("customerId",  unique=True)
    logger.info("Indexes created.")


# ─── Main ─────────────────────────────────────────────────────
def main():
    os.makedirs("logs", exist_ok=True)
    logger.info("=" * 60)
    logger.info("Oracle Views → MongoDB CRM | Migration Started")
    logger.info("=" * 60)

    ora_conn    = get_oracle_conn()
    ora_cursor  = ora_conn.cursor()
    mongo_client = get_mongo_client()
    mongo_db    = mongo_client[MDB_CFG["database"]]

    try:
        create_indexes(mongo_db)
        load_profiles(ora_cursor, mongo_db)
        load_accounts(ora_cursor, mongo_db)
        load_services(ora_cursor, mongo_db)
        load_crm_360(ora_cursor, mongo_db)

        logger.info("=" * 60)
        logger.info("Oracle Views → MongoDB CRM | Completed Successfully")
        logger.info("=" * 60)

    except BulkWriteError as bwe:
        logger.error(f"MongoDB BulkWriteError: {bwe.details}", exc_info=True)
        raise
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
