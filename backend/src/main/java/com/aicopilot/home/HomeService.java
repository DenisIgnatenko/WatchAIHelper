package com.aicopilot.home;

import com.aicopilot.conversation.Conversation;
import com.aicopilot.conversation.ConversationService;
import com.aicopilot.conversation.Message;
import com.aicopilot.draft.Draft;
import com.aicopilot.draft.DraftService;
import com.aicopilot.submission.AiRequest;
import com.aicopilot.submission.SubmissionService;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Assembles the Watch main screen in one call (architecture section 6: fewer round trips over
 * the Watch -> iPhone -> internet path).
 */
@Service
public class HomeService {

 private final ConversationService conversations;
 private final DraftService drafts;
 private final SubmissionService submissions;

 HomeService(ConversationService conversations, DraftService drafts, SubmissionService submissions) {
  this.conversations = conversations;
  this.drafts = drafts;
  this.submissions = submissions;
 }

 @Transactional
 public HomeSnapshot snapshot(UUID userId) {
  Conversation conversation = conversations.activeOrCreate(userId);
  Draft draft = drafts.currentDraft(userId, conversation.id());
  return new HomeSnapshot(
   conversation,
   draft,
   drafts.attachmentCounts(draft.id()),
   submissions.latestForConversation(conversation.id()),
   conversations.lastAnswer(conversation.id()));
 }

 public record HomeSnapshot(
  Conversation conversation,
  Draft draft,
  DraftService.AttachmentCounts draftAttachments,
  Optional<AiRequest> latestRequest,
  Optional<Message> lastAnswer
 ) {
 }
}
