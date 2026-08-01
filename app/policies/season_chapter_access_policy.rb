class SeasonChapterAccessPolicy
  Decision = Struct.new(:allowed, :reason, keyword_init: true) do
    alias_method :allowed?, :allowed

    def initialize(...)
      super
      freeze
    end
  end

  def initialize(user:, chapter:, context: :direct, snapshot_usable: true, at: Time.current)
    @user = user
    @chapter = chapter
    @context = context
    @snapshot_usable = snapshot_usable
    @at = at
  end

  def decision
    return deny(:invalid_snapshot) unless @snapshot_usable
    return deny(:not_public) unless @chapter.is_a?(Hash)
    return deny(:content_unavailable) unless valid_contract?
    return allow if @context == :admin && @user&.admin?

    case @chapter[:status]
    when :draft, :review
      deny(:not_public)
    when :archived
      archived_decision
    when :published
      published_decision
    else
      deny(:content_unavailable)
    end
  end

  private

  def published_decision
    return deny(:not_public) unless %i[publishing completed].include?(@chapter[:season_status])
    return deny(:content_unavailable) unless @chapter[:file_present]
    return allow if @user&.admin? || licensed?

    case @chapter[:access_tier]
    when :guest
      allow
    when :trial
      return deny(:authentication_required) unless @user
      @user.trial_active? ? allow : deny(:trial_required)
    when :license
      @user ? deny(:license_required) : deny(:authentication_required)
    else
      deny(:content_unavailable)
    end
  end

  def archived_decision
    return deny(:not_public) unless @context == :direct
    return deny(:content_unavailable) unless @chapter[:protected] && @chapter[:file_present]

    licensed? ? allow : deny(:archived_license_required)
  end

  def valid_contract?
    @chapter[:product_code] == "chatdox" &&
      @chapter[:id].to_s.match?(/\AS\d{2}E\d{2}\z/) &&
      %i[draft review published archived].include?(@chapter[:status])
  end

  def licensed?
    return false unless @user

    Entitlements::ProductAccess.licensed?(user: @user, product_code: "chatdox", at: @at)
  end

  def allow
    Decision.new(allowed: true, reason: :allowed)
  end

  def deny(reason)
    Decision.new(allowed: false, reason:)
  end
end
