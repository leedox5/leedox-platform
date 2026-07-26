# Loads hq/<product_code>/content_meta.yml -- the data-driven replacement for
# what used to be Ruby constants (Claudox::PHASES/CHAPTER_RANGE/APPENDIX_RANGE/
# NON_CHAPTER_FILES). A product with no file gets sane defaults, so the bare
# minimum for a brand-new product is genuinely zero code and zero config: just
# markdown files under hq/<product_code>/.
#
# Ranges are written as plain "1..8" strings (content_meta.yml is HQ-authored
# content, not Ruby -- Psych's !ruby/range tag would work but isn't something
# a non-Ruby content editor should ever need to know about).
class ProductContent::ContentMeta
  DEFAULT_GUEST_CHAPTER_LIMIT = 2
  DEFAULT_TRIAL_CHAPTER_LIMIT = 5
  DEFAULT_CHAPTER_RANGE = 1..20

  attr_reader :phases, :chapter_range, :appendix_range, :non_chapter_files,
    :guest_chapter_limit, :trial_chapter_limit

  def self.load(directory)
    meta_path = directory.join("content_meta.yml")
    data = File.exist?(meta_path) ? YAML.safe_load(File.read(meta_path), permitted_classes: [ Symbol ], aliases: false) : nil
    new(data || {})
  end

  def initialize(data)
    @phases = (data["phases"] || []).map do |phase|
      {
        key: phase["key"],
        label: phase["label"],
        title: phase["title"],
        description: phase["description"],
        range: parse_range(phase["range"])
      }
    end
    @chapter_range = parse_range(data["chapter_range"]) || DEFAULT_CHAPTER_RANGE
    @appendix_range = parse_range(data["appendix_range"])
    @non_chapter_files = data["non_chapter_files"] || []
    @guest_chapter_limit = data["guest_chapter_limit"] || DEFAULT_GUEST_CHAPTER_LIMIT
    @trial_chapter_limit = data["trial_chapter_limit"] || DEFAULT_TRIAL_CHAPTER_LIMIT
  end

  def licensed_chapter_ranges
    [ chapter_range, appendix_range ].compact
  end

  private

  # A missing key (nil) is a legitimate "not specified" -- callers fall back
  # to a sane default for that. A *present* value that's malformed or
  # reversed is an operator mistake, not a missing-config case, so it raises
  # instead of silently degrading into that same default (which would hide
  # the mistake rather than surface it at content-load time).
  def parse_range(value)
    return nil if value.nil?

    match = value.to_s.match(/\A(\d+)\.\.(\d+)\z/)
    raise ArgumentError, "invalid range in content_meta.yml: #{value.inspect} (expected \"N..M\")" unless match

    low, high = match[1].to_i, match[2].to_i
    raise ArgumentError, "reversed range in content_meta.yml: #{value.inspect} (#{low} > #{high})" if low > high

    Range.new(low, high)
  end
end
