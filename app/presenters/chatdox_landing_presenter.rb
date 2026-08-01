class ChatdoxLandingPresenter
  SeasonCard = Data.define(
    :code, :title, :description, :status, :status_label, :public_count,
    :progress, :cta_label, :cta_path
  )

  COPY = {
    "s01" => {
      title: "S01. AI와 SaaS 구축하기",
      description: "아이디어에서 시작해 인증, 결제, 운영 기능과 배포까지 실제 SaaS 하나를 완성한 과정"
    },
    "s02" => {
      title: "S02. SaaS에서 플랫폼으로",
      description: "운영 중인 SaaS의 과거 가정을 고치고, Work와 함께 운영과 사업 활용으로 확장하는 과정"
    }
  }.freeze

  attr_reader :user, :routes, :source, :summary

  def initialize(user:, routes:)
    @user = user
    @routes = routes
    @source = canonical_ready? ? ProductContent.seasoned_chatdox : ProductContent.for("chatdox")
    @summary = ProductContent::ProgressSummary.call(user:, source:)
  end

  def canonical_ready?
    return @canonical_ready if defined?(@canonical_ready)

    @canonical_ready = ProductContent.chatdox_source_mode == "seasoned" && ProductContent.seasoned_chatdox.usable?
  end

  def seasons
    @seasons ||= %w[s01 s02].map { |code| build_season(code) }.freeze
  end

  def primary_cta
    seasons.first.then { |season| { label: season.cta_label, path: season.cta_path } }
  end

  def licensed?
    user&.licensed_for?("chatdox") || false
  end

  private

  def build_season(code)
    metadata = canonical_ready? ? source.seasons.find { |season| season[:code] == code } : nil
    progress = summary.season(code)
    public_count = metadata ? metadata[:public_episode_count] : (code == "s01" ? source.public_chapters.size : 0)
    status = metadata&.fetch(:status) || (code == "s01" ? :completed : :upcoming)
    cta_label, cta_path = season_cta(code, progress, public_count)

    SeasonCard.new(
      code:, title: COPY.fetch(code).fetch(:title), description: COPY.fetch(code).fetch(:description),
      status:, status_label: status == :upcoming ? "준비 중" : (status == :publishing ? "연재 중" : "완료"),
      public_count:, progress:, cta_label:, cta_path:
    ).freeze
  end

  def season_cta(code, progress, public_count)
    return s02_cta if code == "s02" && public_count.zero?

    chapter = progress&.next_chapter
    if canonical_ready? && chapter && accessible?(chapter)
      label = progress.completed_count.zero? ? "첫 에피소드 읽기" : "학습 이어가기"
      return [ label, routes.chatdox_episode_path(chapter[:season_code], chapter[:display_number]) ]
    end

    if canonical_ready?
      [ progress&.complete? ? "완료한 시즌 다시 보기" : "시즌 보기", routes.chatdox_season_path(code) ]
    elsif ProductContent.chatdox_source_mode == "legacy"
      [ progress&.completed_count.to_i.positive? ? "학습 이어가기" : "첫 에피소드 읽기", routes.doc_path("01") ]
    else
      [ "콘텐츠 준비 중", nil ]
    end
  end

  def s02_cta
    canonical_ready? ? [ "S02 준비 이야기 보기", routes.chatdox_season_path("s02") ] : [ "S02 공개 준비 중", nil ]
  end

  def accessible?(chapter)
    SeasonChapterAccessPolicy.new(user:, chapter:, context: :direct).decision.allowed?
  end
end
