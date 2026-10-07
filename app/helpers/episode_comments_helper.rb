# Handoff 0074 -- how a comment's author and time read on the customer episode page.
module EpisodeCommentsHelper
  # The account's name masked (0074 R2): never the full name, never the email. An admin's comment
  # reads "LEEDOX" with a 운영자 badge; a deleted account reads "탈퇴한 사용자".
  def comment_author_label(comment)
    user = comment.user
    if user.nil?
      tag.span("탈퇴한 사용자", class: "font-semibold text-ink-3")
    elsif user.admin?
      safe_join([ tag.span("LEEDOX", class: "font-bold text-ink"),
        tag.span("운영자", class: "ml-1.5 rounded-full bg-accent px-2 py-0.5 text-[11px] font-bold text-on-accent") ])
    else
      tag.span(masked_name(user.name), class: "font-semibold text-ink")
    end
  end

  # First character + "**" whatever the length ("이명호" -> "이**", "Tommy" -> "T**"), so the name's
  # length isn't revealed either; "회원" for a blank name. The first grapheme, not the first byte or
  # codepoint, so a combined character or emoji isn't cut in half.
  def masked_name(name)
    first = name.to_s.strip.each_grapheme_cluster.first
    first ? "#{first}**" : "회원"
  end

  def comment_time(comment)
    comment.created_at.strftime("%Y.%m.%d %H:%M")
  end

  # What a top-level comment that's no longer visible shows while its replies remain.
  def comment_placeholder(comment)
    comment.hidden? ? "운영자가 숨긴 댓글입니다" : "삭제된 댓글입니다"
  end
end
