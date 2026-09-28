package com.aicopilot.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Clock;
import java.util.Optional;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Minimum secure client authentication for a private app (spec 45): {@code Authorization: Bearer <device token>}
 * on every {@code /v1/**} request. No sessions, no cookies, no user accounts UI (YAGNI).
 */
@Component
class DeviceTokenFilter extends OncePerRequestFilter {

 private static final String BEARER = "Bearer ";

 private final DeviceRepository devices;
 private final Clock clock;

 DeviceTokenFilter(DeviceRepository devices, Clock clock) {
  this.devices = devices;
  this.clock = clock;
 }

 @Override
 protected boolean shouldNotFilter(HttpServletRequest request) {
  // Only the API is protected; /actuator/health stays public for the deployment health check.
  return !request.getRequestURI().startsWith("/v1/");
 }

 @Override
 protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
  throws ServletException, IOException {
  Optional<UUID> userId = bearerToken(request).flatMap(token -> {
   String hash = TokenHasher.sha256Hex(token);
   Optional<UUID> owner = devices.findUserIdByTokenHash(hash);
   owner.ifPresent(ignored -> devices.touch(hash, clock.instant()));
   return owner;
  });
  if (userId.isEmpty()) {
   reject(response);
   return;
  }
  request.setAttribute(CurrentUser.ATTRIBUTE, userId.get());
  chain.doFilter(request, response);
 }

 private static Optional<String> bearerToken(HttpServletRequest request) {
  String header = request.getHeader("Authorization");
  if (header == null || !header.startsWith(BEARER) || header.length() <= BEARER.length()) {
   return Optional.empty();
  }
  return Optional.of(header.substring(BEARER.length()).trim());
 }

 /** RFC 9457 problem body, the same format as all other API errors. */
 private static void reject(HttpServletResponse response) throws IOException {
  response.setStatus(HttpStatus.UNAUTHORIZED.value());
  response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
  response.getWriter().write(
   "{\"title\":\"Unauthorized\",\"status\":401,\"code\":\"unauthorized\",\"detail\":\"Missing or invalid device token\"}");
 }
}
