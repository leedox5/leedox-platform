require "test_helper"
require "open3"
require "tmpdir"
require "tailwindcss/ruby"

# Handoff 0084 R2 (backlog 0064) -- checks the *built* CSS, not class strings in HTML. Tailwind's scanner drops classes
# that follow an arbitrary hex class inside an ERB Ruby string (`dark ? "text-[#c9c4ba] hover:bg-white/5" : ...`);
# nothing errors, the class just has no CSS. That left the dark header's own background (`bg-[#0e1014]/90`)
# unbuilt -- a transparent header -- from 0071 to 0084 while every HTML-level test passed.
#
# This builds the app's CSS with the real Tailwind CLI and asserts that every color class with an arbitrary hex value
# or a white/black opacity (the kinds this bug hits) written anywhere in app/views or app/helpers exists in it.
class TailwindBuildTest < ActiveSupport::TestCase
  COLOR_CLASS = %r{(?<![\w\[-])((?:[a-z-]+:)*-?[a-z][a-z-]*-(?:\[\#[0-9a-fA-F]{3,8}\]|white|black)(?:/\d+)?)(?![\w\]\[/-])}

  def built_css
    Dir.mktmpdir do |dir|
      out = File.join(dir, "tailwind.css")
      _stdout, stderr, status = Open3.capture3(Tailwindcss::Ruby.executable, "-i", Rails.root.join("app/assets/tailwind/application.css").to_s,
        "-o", out, chdir: Rails.root.to_s)
      assert status.success?, "tailwind build failed: #{stderr}"
      File.read(out)
    end
  end

  def selector(klass)
    "." + klass.gsub(/([:\[\]#\/.])/) { "\\#{Regexp.last_match(1)}" }
  end

  test "every hex / white / black color class used in views and helpers is in the built CSS" do
    files = Dir[Rails.root.join("app/views/**/*.erb")] + Dir[Rails.root.join("app/helpers/**/*.rb")]
    used = files.each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, acc|
      File.read(file).scan(COLOR_CLASS).flatten.uniq.each { |klass| acc[klass] << file.delete_prefix("#{Rails.root}/") }
    end
    assert used.key?("bg-[#0e1014]/90"), "the scan should see the dark header background"

    css = built_css
    missing = used.reject { |klass, _| css.include?(selector(klass)) }
    assert_empty missing, "classes with no CSS (Tailwind didn't extract them):\n" +
      missing.map { |klass, where| "  #{klass}  <- #{where.uniq.join(', ')}" }.join("\n")
  end

  test "the frame and series theme tables only hold classes that are built" do
    css = built_css
    tables = FrameThemeHelper::FRAME_THEME.values.flatten + [ FrameThemeHelper::FOOTER_LINK_CLASS ] +
      FrameThemeHelper::BODY_CLASS.values + SeriesThemeHelper::SERIES_THEME.values.flatten # BODY_CLASS: 0100
    classes = tables.flat_map(&:split).uniq.select { |klass| klass.match?(/\[#|\/\d+\z|\A\[color-scheme/) }
    missing = classes.reject { |klass| css.include?(selector(klass)) }
    assert_empty missing
  end
end
