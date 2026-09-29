package com.aicopilot.api;

import com.aicopilot.api.generated.UsageApi;
import com.aicopilot.api.generated.model.UsageReportDto;
import com.aicopilot.auth.CurrentUser;
import com.aicopilot.usage.UsageService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class UsageController implements UsageApi {

 private final UsageService usage;
 private final CurrentUser currentUser;
 private final ApiMapper mapper;

 UsageController(UsageService usage, CurrentUser currentUser, ApiMapper mapper) {
  this.usage = usage;
  this.currentUser = currentUser;
  this.mapper = mapper;
 }

 @Override
 public ResponseEntity<UsageReportDto> getUsage() {
  return ResponseEntity.ok(mapper.usage(usage.report(currentUser.id())));
 }
}
