package com.aicopilot.auth;

import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

/**
 * The authenticated user of the current HTTP request (set by {@link DeviceTokenFilter}).
 * Controllers ask this component instead of parsing headers themselves (SRP).
 */
@Component
public class CurrentUser {

 static final String ATTRIBUTE = CurrentUser.class.getName() + ".userId";

 public UUID id() {
  Object value = RequestContextHolder.currentRequestAttributes()
   .getAttribute(ATTRIBUTE, RequestAttributes.SCOPE_REQUEST);
  if (value instanceof UUID userId) {
   return userId;
  }
  // Unreachable for /v1/** because the filter rejects unauthenticated requests earlier.
  throw new IllegalStateException("No authenticated user in this request");
 }
}
