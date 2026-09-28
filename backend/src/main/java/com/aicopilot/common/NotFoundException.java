package com.aicopilot.common;

/**
 * The entity does not exist or belongs to another user. Both cases look the same to the client,
 * so the API never reveals other users' ids.
 */
public class NotFoundException extends RuntimeException {

 public NotFoundException(String what) {
  super(what + " not found");
 }
}
