package com.aicopilot.api;

import com.aicopilot.api.generated.model.AiRequestDto;
import com.aicopilot.api.generated.model.AttachmentDto;
import com.aicopilot.api.generated.model.AttachmentSourceDto;
import com.aicopilot.api.generated.model.DraftDetailDto;
import com.aicopilot.api.generated.model.ConversationDto;
import com.aicopilot.api.generated.model.ConversationModeDto;
import com.aicopilot.api.generated.model.DraftSummaryDto;
import com.aicopilot.api.generated.model.HomeSnapshotDto;
import com.aicopilot.api.generated.model.MessageDto;
import com.aicopilot.api.generated.model.SuggestedActionDto;
import com.aicopilot.api.generated.model.UsagePeriodDto;
import com.aicopilot.api.generated.model.UsageReportDto;
import com.aicopilot.conversation.Conversation;
import com.aicopilot.conversation.Message;
import com.aicopilot.draft.Attachment;
import com.aicopilot.draft.AttachmentService.DraftDetail;
import com.aicopilot.draft.Draft;
import com.aicopilot.draft.DraftService;
import com.aicopilot.draft.DraftService.AttachmentCounts;
import com.aicopilot.home.HomeService.HomeSnapshot;
import com.aicopilot.submission.AiRequest;
import com.aicopilot.usage.UsageService.Period;
import com.aicopilot.usage.UsageService.UsageReport;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import org.springframework.stereotype.Component;

/**
 * Domain -> transport DTO mapping (spec 52: DTOs and domain models stay separate).
 * The only class that knows both shapes.
 */
@Component
class ApiMapper {

 private final DraftService drafts;

 ApiMapper(DraftService drafts) {
  this.drafts = drafts;
 }

 HomeSnapshotDto home(HomeSnapshot home) {
  AttachmentCounts counts = home.draftAttachments();
  var draft = new DraftSummaryDto(home.draft().id(), counts.total(), counts.uploaded(), counts.failed())
   .text(home.draft().text());
  var dto = new HomeSnapshotDto(conversation(home.conversation()), draft);
  home.latestRequest().ifPresent(r -> dto.latestRequest(request(r)));
  home.lastAnswer().ifPresent(m -> dto.lastAnswer(message(m)));
  return dto;
 }

 DraftDetailDto draftDetail(DraftDetail detail) {
  Draft d = detail.draft();
  var state = switch (d.state()) {
   case OPEN -> DraftDetailDto.StateEnum.OPEN;
   case FROZEN -> DraftDetailDto.StateEnum.FROZEN;
   case CONSUMED -> DraftDetailDto.StateEnum.CONSUMED;
  };
  return new DraftDetailDto(d.id(), d.conversationId(), state, detail.attachments().stream().map(this::attachment).toList())
   .text(d.text());
 }

 AttachmentDto attachment(Attachment a) {
  var state = switch (a.state()) {
   case PENDING -> AttachmentDto.StateEnum.PENDING;
   case UPLOADED -> AttachmentDto.StateEnum.UPLOADED;
   case FAILED -> AttachmentDto.StateEnum.FAILED;
  };
  var source = a.source() == Attachment.Source.CAMERA ? AttachmentSourceDto.CAMERA : AttachmentSourceDto.PHOTO_LIBRARY;
  return new AttachmentDto(a.id(), a.draftId(), a.position(), source, state, a.mimeType(), a.byteSize())
   .failureReason(a.failureReason());
 }

 ConversationDto conversation(Conversation c) {
  var mode = c.mode() == Conversation.Mode.DANISH_EXAM ? ConversationModeDto.DANISH_EXAM : ConversationModeDto.GENERAL;
  return new ConversationDto(c.id(), c.title(), mode, time(c.updatedAt()));
 }

 MessageDto message(Message m) {
  var role = m.role() == Message.Role.USER ? MessageDto.RoleEnum.USER : MessageDto.RoleEnum.ASSISTANT;
  var actions = m.suggestedActions().stream().map(a -> new SuggestedActionDto(a.title(), a.prompt())).toList();
  return new MessageDto(m.id(), m.conversationId(), role, m.attachmentCount(), actions, time(m.createdAt()))
   .text(m.text());
 }

 AiRequestDto request(AiRequest r) {
  var dto = new AiRequestDto(r.id(), r.conversationId(), time(r.createdAt()), state(r.state()));
  switch (r.state()) {
   case WAITING_FOR_ATTACHMENTS -> {
    AttachmentCounts counts = drafts.attachmentCounts(r.draftId());
    dto.uploadedAttachments(counts.uploaded()).totalAttachments(counts.total());
   }
   case BLOCKED -> dto.failedAttachments(drafts.attachmentCounts(r.draftId()).failed());
   case COMPLETED -> dto.assistantMessageId(r.assistantMessageId());
   case FAILED -> dto.failureReason(failureReason(r.lastErrorCode()));
   default -> {
   }
  }
  return dto;
 }

 UsageReportDto usage(UsageReport report) {
  return new UsageReportDto(report.currency(), report.timeZone(), period(report.today()), period(report.month()),
   period(report.total()));
 }

 private static UsagePeriodDto period(Period p) {
  return new UsagePeriodDto(p.answers(), p.inputTokens(), p.cachedInputTokens(), p.outputTokens(), p.cost().doubleValue());
 }

 private static AiRequestDto.StateEnum state(AiRequest.State state) {
  return switch (state) {
   case WAITING_FOR_ATTACHMENTS -> AiRequestDto.StateEnum.WAITING_FOR_ATTACHMENTS;
   case BLOCKED -> AiRequestDto.StateEnum.BLOCKED;
   case QUEUED -> AiRequestDto.StateEnum.QUEUED;
   case PROCESSING -> AiRequestDto.StateEnum.PROCESSING;
   case COMPLETED -> AiRequestDto.StateEnum.COMPLETED;
   case FAILED -> AiRequestDto.StateEnum.FAILED;
   case CANCELLED -> AiRequestDto.StateEnum.CANCELLED;
  };
 }

 /** Short, user-safe text for the Watch. Internal codes stay in the database and logs. */
 private static String failureReason(String code) {
  if (code == null) {
   return "Could not get an answer";
  }
  if (code.equals("rate_limited") || code.startsWith("provider_error") || code.equals("provider_unreachable")) {
   return "AI service unavailable";
  }
  return "Could not get an answer";
 }

 private static OffsetDateTime time(Instant instant) {
  return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
 }
}
