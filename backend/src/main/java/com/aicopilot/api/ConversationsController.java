package com.aicopilot.api;

import com.aicopilot.api.generated.ConversationsApi;
import com.aicopilot.api.generated.model.ConversationDto;
import com.aicopilot.api.generated.model.ConversationModeDto;
import com.aicopilot.api.generated.model.CreateConversationRequestDto;
import com.aicopilot.api.generated.model.MessageDto;
import com.aicopilot.api.generated.model.RenameConversationRequestDto;
import com.aicopilot.api.generated.model.SetActiveConversationRequestDto;
import com.aicopilot.auth.CurrentUser;
import com.aicopilot.conversation.Conversation;
import com.aicopilot.conversation.ConversationService;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class ConversationsController implements ConversationsApi {

 private final ConversationService conversations;
 private final CurrentUser currentUser;
 private final ApiMapper mapper;

 ConversationsController(ConversationService conversations, CurrentUser currentUser, ApiMapper mapper) {
  this.conversations = conversations;
  this.currentUser = currentUser;
  this.mapper = mapper;
 }

 @Override
 public ResponseEntity<List<ConversationDto>> listConversations() {
  return ResponseEntity.ok(conversations.list(currentUser.id()).stream().map(mapper::conversation).toList());
 }

 @Override
 public ResponseEntity<ConversationDto> createConversation(CreateConversationRequestDto request) {
  var mode = request.getMode() == ConversationModeDto.DANISH_EXAM ? Conversation.Mode.DANISH_EXAM : Conversation.Mode.GENERAL;
  var created = conversations.create(currentUser.id(), request.getId(), mode);
  return ResponseEntity.status(HttpStatus.CREATED).body(mapper.conversation(created));
 }

 @Override
 public ResponseEntity<ConversationDto> renameConversation(UUID conversationId, RenameConversationRequestDto request) {
  return ResponseEntity.ok(mapper.conversation(conversations.rename(currentUser.id(), conversationId, request.getTitle())));
 }

 @Override
 public ResponseEntity<Void> deleteConversation(UUID conversationId) {
  conversations.delete(currentUser.id(), conversationId);
  return ResponseEntity.noContent().build();
 }

 @Override
 public ResponseEntity<Void> setActiveConversation(SetActiveConversationRequestDto request) {
  conversations.setActive(currentUser.id(), request.getConversationId());
  return ResponseEntity.noContent().build();
 }

 @Override
 public ResponseEntity<List<MessageDto>> listMessages(UUID conversationId) {
  return ResponseEntity.ok(conversations.messages(currentUser.id(), conversationId).stream().map(mapper::message).toList());
 }
}
