package com.aicopilot.ai;

/**
 * AI call failure with a stable code for storage/logs and a retry hint.
 *
 * <p>Transient: rate limit, provider 5xx, timeout, network - another attempt later may succeed.
 * Permanent: bad request, authentication, invalid model output - retrying the same input will not help.
 */
public class AiEngineException extends RuntimeException {

 private final String code;
 private final boolean transientFailure;

 public AiEngineException(String code, boolean transientFailure, String message, Throwable cause) {
  super(message, cause);
  this.code = code;
  this.transientFailure = transientFailure;
 }

 public static AiEngineException transientFailure(String code, String message, Throwable cause) {
  return new AiEngineException(code, true, message, cause);
 }

 public static AiEngineException permanent(String code, String message, Throwable cause) {
  return new AiEngineException(code, false, message, cause);
 }

 public String code() {
  return code;
 }

 public boolean isTransient() {
  return transientFailure;
 }
}
