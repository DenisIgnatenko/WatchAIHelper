package com.aicopilot.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * Device tokens are stored only as SHA-256 hashes: a database leak does not reveal usable tokens.
 * A plain (unsalted) hash is sufficient because tokens are 256-bit random values, not passwords.
 */
final class TokenHasher {

 private TokenHasher() {
 }

 static String sha256Hex(String token) {
  try {
   byte[] digest = MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8));
   return HexFormat.of().formatHex(digest);
  } catch (NoSuchAlgorithmException e) {
   throw new IllegalStateException("SHA-256 is always available in the JDK", e);
  }
 }
}
