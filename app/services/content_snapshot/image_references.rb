require "uri"

module ContentSnapshot
  class ImageReferences
    def self.extract(markdown, season_code:, images_dir:)
      new(markdown, season_code:, images_dir:).extract
    end

    def initialize(markdown, season_code:, images_dir:)
      @markdown = markdown
      @season_code = season_code
      @images_dir = images_dir
    end

    def extract
      document.css("img").filter_map { |node| normalize(node["src"]) }.uniq.sort
    end

    private

    def document
      renderer = Redcarpet::Render::HTML.new
      html = Redcarpet::Markdown.new(renderer, fenced_code_blocks: true).render(@markdown)
      Nokogiri::HTML.fragment(html)
    end

    def normalize(source)
      return if source.blank? || source.include?("\\")

      uri = URI.parse(source)
      return if uri.host || (uri.scheme && uri.scheme != "")

      path = uri.path
      prefixes = [
        "/docs/images/",
        "/chatdox/#{@season_code}/images/",
        "#{@images_dir}/",
        "./#{@images_dir}/"
      ]
      prefix = prefixes.find { |candidate| path.start_with?(candidate) }
      return unless prefix

      relative = path.delete_prefix(prefix)
      pathname = Pathname.new(relative)
      return if relative.blank? || pathname.absolute? || pathname.each_filename.any? { |part| part == ".." }

      pathname.each_filename.to_a.join("/")
    rescue URI::InvalidURIError
      nil
    end
  end
end
