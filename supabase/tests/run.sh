#!/bin/sh
# ใช้ Postgres ในเครื่อง: PGHOST/PGPORT/PGUSER ชี้ไปที่เซิร์ฟเวอร์ทดสอบ ฐาน dormtest จะถูกลบแล้วสร้างใหม่
set -e
cd "$(dirname "$0")"
P="psql -v ON_ERROR_STOP=1 -q -o /dev/null"
$P -d postgres -c "drop database if exists dormtest" -c "create database dormtest"
$P -d dormtest -f 00_stub_supabase.sql $(for m in ../migrations/*.sql; do printf -- '-f %s ' "$m"; done) -f 10_flow_test.sql -f 20_water_test.sql -f 30_water_rules_test.sql
