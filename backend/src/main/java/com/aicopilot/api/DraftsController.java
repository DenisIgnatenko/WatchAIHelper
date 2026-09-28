package com.aicopilot.api;

import com.aicopilot.api.generated.DraftsApi;
import com.aicopilot.api.generated.model.AttachmentDto;
import com.aicopilot.api.generated.model.DraftDetailDto;
import com.aicopilot.api.generated.model.RegisterAttachmentRequestDto;
import com.aicopilot.auth.CurrentUser;
import com.aicopilot.conversation.ConversationService;
import com.aicopilot.draft.Attachment;
import com.aicopilot.draft.AttachmentService;
import com.aicopilot.draft.AttachmentService.NewAttachment;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.UUID;
import org.springframework.core.io.Resource;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class DraftsController implements DraftsApi {

 private final AttachmentService attachments;
 private final ConversationService conversations;
 private final CurrentUser currentUser;
 private final ApiMapper mapper;

 DraftsController(AttachmentService attachments, ConversationService conversations, CurrentUser currentUser,
  ApiMapper mapper) {
  this.attachments = attachments;
  this.conversations = conversations;
  this.currentUser = currentUser;
  this.mapper = mapper;
 }

 @Override
 public ResponseEntity<DraftDetailDto> getCurrentDraft(UUID conversationId) {
  UUID userId = currentUser.id();
  conversations.get(userId, conversationId);
  return ResponseEntity.ok(mapper.draftDetail(attachments.detail(userId, conversationId)));
 }

 @Override
 public ResponseEntity<AttachmentDto> registerAttachment(UUID draftId, UUID attachmentId, RegisterAttachmentRequestDto r) {
  var source = r.getSource() == com.aicopilot.api.generated.model.AttachmentSourceDto.CAMERA
   ? Attachment.Source.CAMERA : Attachment.Source.PHOTO_LIBRARY;
  var request = new NewAttachment(source, r.getMimeType().getValue(), r.getByteSize(), r.getSha256(), r.getWidth(),
   r.getHeight());
  return ResponseEntity.ok(mapper.attachment(attachments.register(currentUser.id(), draftId, attachmentId, request)));
 }

 @Override
 public ResponseEntity<Void> removeAttachment(UUID draftId, UUID attachmentId) {
  attachments.remove(currentUser.id(), draftId, attachmentId);
  return ResponseEntity.noContent().build();
 }

 /** The raw request body is streamed straight to storage; it is never fully held in memory here. */
 @Override
 public ResponseEntity<AttachmentDto> uploadAttachmentContent(UUID attachmentId, Resource body) {
  try (InputStream content = body.getInputStream()) {
   return ResponseEntity.ok(mapper.attachment(attachments.upload(currentUser.id(), attachmentId, content)));
  } catch (IOException e) {
   throw new UncheckedIOException(e);
  }
 }
}
