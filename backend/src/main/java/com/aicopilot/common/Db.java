package com.aicopilot.common;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/** Small JDBC helpers shared by repositories (DRY for timestamp conversions). */
public final class Db {

 private Db() {
 }

 /** Bind value for a {@code timestamptz} column. */
 public static OffsetDateTime ts(Instant instant) {
  return instant == null ? null : OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
 }

 /** Read a {@code timestamptz} column; null-safe. */
 public static Instant instant(ResultSet rs, String column) throws SQLException {
  OffsetDateTime value = rs.getObject(column, OffsetDateTime.class);
  return value == null ? null : value.toInstant();
 }
}
