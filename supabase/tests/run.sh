#!/bin/sh
# ใช้ Postgres ในเครื่อง: PGHOST/PGPORT/PGUSER ชี้ไปที่เซิร์ฟเวอร์ทดสอบ ฐาน dormtest จะถูกลบแล้วสร้างใหม่
set -e
cd "$(dirname "$0")"
P="psql -v ON_ERROR_STOP=1 -q -o /dev/null"
$P -d postgres -c "drop database if exists dormtest" -c "create database dormtest"
$P -d dormtest -f 00_stub_supabase.sql -f ../migrations/20261106000000_init.sql -f 10_flow_test.sql
