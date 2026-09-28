package com.aicopilot.api;

import com.aicopilot.api.generated.HomeApi;
import com.aicopilot.api.generated.model.HomeSnapshotDto;
import com.aicopilot.auth.CurrentUser;
import com.aicopilot.home.HomeService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class HomeController implements HomeApi {

 private final HomeService home;
 private final CurrentUser currentUser;
 private final ApiMapper mapper;

 HomeController(HomeService home, CurrentUser currentUser, ApiMapper mapper) {
  this.home = home;
  this.currentUser = currentUser;
  this.mapper = mapper;
 }

 @Override
 public ResponseEntity<HomeSnapshotDto> getHome() {
  return ResponseEntity.ok(mapper.home(home.snapshot(currentUser.id())));
 }
}
