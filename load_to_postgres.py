"""
Loads the cleaned CSVs directly into a PostgreSQL database using pandas +
SQLAlchemy. Once this runs, refresh pgAdmin (right-click your database ->
Refresh) and the tables will appear under Schemas -> public -> Tables.

SETUP (run once in your terminal, not in this script):
    pip install sqlalchemy psycopg2-binary pandas python-dotenv

FILL IN your actual pgAdmin/Postgres connection details in your .env file before running.
These are the same details pgAdmin used when you created the server
connection (usually host=localhost, port=5432, and whatever DB name you
created, e.g. "sales_funnel_project").
"""

import os
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

# ---- 1. CONNECTION DETAILS -- read from the .env file -------------------
# Put your details in a file called .env next to this script (see .env.example).
# .env is listed in .gitignore, so your password never goes to GitHub.
load_dotenv()

DB_USER = os.getenv("PGUSER", "postgres")
DB_PASSWORD = os.getenv("PGPASSWORD", "")
DB_HOST = os.getenv("PGHOST", "localhost")
DB_PORT = os.getenv("PGPORT", "5432")
DB_NAME = os.getenv("PGDATABASE", "sales_funnel_project")

# ---- 2. Build the connection engine ---------------------------------------
engine = create_engine(
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# ---- 3. Load each cleaned CSV and push it to Postgres ----------------------
# if_exists="replace" drops and recreates the table each time you run this
# script -- convenient while you're iterating; switch to "append" later if
# you want to add rows instead of overwriting.
files_to_tables = {
    "data_cleaned/sales_pipeline_cleaned.csv": "sales_pipeline_cleaned",
    "data_cleaned/accounts_cleaned.csv": "accounts_cleaned",
    "data_cleaned/products_cleaned.csv": "products_cleaned",
    "data_cleaned/sales_teams_cleaned.csv": "sales_teams_cleaned",
    "data_cleaned/lead_sources_cleaned.csv": "lead_sources_cleaned",
}

for csv_path, table_name in files_to_tables.items():
    df = pd.read_csv(csv_path)

    # Parse date columns properly so Postgres stores them as DATE/TIMESTAMP,
    # not TEXT -- this matters for the date-math queries in Phase 1.
    for date_col in ["engage_date", "close_date",
                      "lead_created_date", "mql_date", "sql_date"]:
        if date_col in df.columns:
            df[date_col] = pd.to_datetime(df[date_col])

    df.to_sql(table_name, engine, if_exists="replace", index=False)
    print(f"Loaded {len(df):>5} rows -> table '{table_name}'")

print("\nDone. Refresh pgAdmin (right-click the database -> Refresh) to see the tables.")
