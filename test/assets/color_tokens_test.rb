require "test_helper"
require "open3"
require "tmpdir"
require "tailwindcss/ruby"

# Handoff 0101 (D-014 step 1) -- the customer pages' dark palette is named by role in application.css's @theme. The
# values must stay exactly what the classes used before (nothing may look different until the light mode, step 2), so
# this pins every token to its hex in the *built* CSS, and checks the views and helpers no longer write a hex color
# class of their own.
class ColorTokensTest < ActiveSupport::TestCase
  # token => the value it had as an arbitrary class before 0101 (white: border-white/NN, bg-white/NN)
  TOKENS = {
    "page" => "#0e1014", "card" => "#15181e",
    "ink" => "#f2efe8", "ink-2" => "#c9c4ba", "ink-3" => "#a8a39a",
    "accent" => "#f0a53c", "accent-hover" => "#f5b85e", "accent-ink" => "#f0a53c", "accent-ink-hover" => "#f5b85e",
    "accent-soft" => "#f0a53c",
    "ok" => "#7dd3a8", "ok-hover" => "#9be0bd", "ok-ink" => "#7dd3a8", "ok-soft" => "#7dd3a8",
    "on-accent" => "#0e1014", "danger" => "#ff8a80",
    "line" => "#ffffff", "tint" => "#ffffff",
    "cover-1" => "#1b1e25", "cover-2" => "#161920", "cover-3" => "#0e1014"
  }.freeze

  def built_css
    Dir.mktmpdir do |dir|
      out = File.join(dir, "tailwind.css")
      _stdout, stderr, status = Open3.capture3(Tailwindcss::Ruby.executable, "-i", Rails.root.join("app/assets/tailwind/application.css").to_s,
        "-o", out, chdir: Rails.root.to_s)
      assert status.success?, "tailwind build failed: #{stderr}"
      File.read(out)
    end
  end

  def long_hex(value)
    hex = value.strip.downcase.delete_prefix("#")
    hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
    "##{hex}"
  end

  test "every token is defined in application.css, and nothing else is" do
    defined = File.read(Rails.root.join("app/assets/tailwind/application.css")).scan(/--color-([a-z0-9-]+):\s*(#[0-9a-fA-F]{3,8})/).to_h
    assert_equal TOKENS.keys.sort, defined.keys.sort
    TOKENS.each { |name, hex| assert_equal hex, long_hex(defined[name]), name }
  end

  test "the built CSS carries each token with exactly the old value" do
    css = built_css
    built = css.scan(/--color-([a-z0-9-]+):\s*([^;}]+)/).to_h
    TOKENS.each do |name, hex|
      assert built.key?(name), "--color-#{name} is not in the built CSS"
      assert_equal hex, long_hex(built[name]), "--color-#{name}"
    end
  end

  test "views and helpers write no hex color class of their own any more" do
    files = Dir[Rails.root.join("app/views/**/*.erb")] + Dir[Rails.root.join("app/helpers/**/*.rb")]
    left = files.flat_map do |file|
      File.read(file).scan(/[a-z:-]*-\[#[0-9a-fA-F]{3,8}\](?:\/\d+)?/).map { |klass| "#{file.delete_prefix("#{Rails.root}/")}: #{klass}" }
    end
    assert_empty left
    css = File.read(Rails.root.join("app/assets/tailwind/application.css")).gsub(%r{/\*.*?\*/}m, "")
    assert_no_match(/-\[#[0-9a-fA-F]{3,8}\]/, css, "application.css (outside comments)")
  end
end
