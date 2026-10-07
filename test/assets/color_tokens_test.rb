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

  # Handoff 0102 (D-014 step 2) -- the light values ([data-theme="light"]): HQ / Tommy's candidate A, "warm paper".
  LIGHT = {
    "page" => "#f5f2ea", "card" => "#fffefb",
    "ink" => "#1c1b18", "ink-2" => "#45423b", "ink-3" => "#6b665d",
    "accent" => "#f0a53c", "accent-hover" => "#e8962a", "accent-ink" => "#8f520e", "accent-ink-hover" => "#6f3f08",
    "accent-soft" => "#b4690f",
    "ok" => "#7dd3a8", "ok-hover" => "#66c597", "ok-ink" => "#05684a", "ok-soft" => "#0a7a57",
    "on-accent" => "#0e1014", "danger" => "#b3261e",
    "line" => "#1c1b18", "tint" => "#1c1b18",
    "cover-1" => "#ebe6da", "cover-2" => "#e0dacb", "cover-3" => "#d6cfbe"
  }.freeze

  SOURCE = File.read(Rails.root.join("app/assets/tailwind/application.css"))

  def self.css_build
    @css_build ||= Dir.mktmpdir do |dir|
      out = File.join(dir, "tailwind.css")
      _stdout, stderr, status = Open3.capture3(Tailwindcss::Ruby.executable, "-i", Rails.root.join("app/assets/tailwind/application.css").to_s,
        "-o", out, chdir: Rails.root.to_s)
      raise "tailwind build failed: #{stderr}" unless status.success?

      File.read(out)
    end
  end

  # {name => value} of the --color-* declarations inside the first block whose head matches `opener`
  def token_block(css, opener)
    head = css.match(opener) or flunk("no #{opener.source} block")
    body = css[head.end(0)..].split("}", 2).first
    body.scan(/--color-([a-z0-9-]+):\s*([^;}]+)/).to_h { |name, value| [ name, long_hex(value) ] }
  end

  def luminance(hex)
    hex.delete_prefix("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
      .map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
      .zip([ 0.2126, 0.7152, 0.0722 ]).sum { |c, w| c * w }
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].minmax.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  def long_hex(value)
    hex = value.strip.downcase.delete_prefix("#")
    hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
    "##{hex}"
  end

  test "every token is defined in application.css's @theme, and nothing else is" do
    defined = token_block(SOURCE, /@theme \{/)
    assert_equal TOKENS.keys.sort, defined.keys.sort
    TOKENS.each { |name, hex| assert_equal hex, defined[name], name }
  end

  test "the built CSS carries each token with exactly the old value (the dark side, the default)" do
    built = token_block(self.class.css_build, /:root,\s*:host\s*\{/)
    TOKENS.each do |name, hex|
      assert built.key?(name), "--color-#{name} is not in the built CSS"
      assert_equal hex, built[name], "--color-#{name}"
    end
  end

  # Handoff 0102
  test "the light values, in the source and in the built CSS, are exactly HQ's table -- every token, nothing else" do
    [ token_block(SOURCE, /\[data-theme="light"\] \{/), token_block(self.class.css_build, /\[data-theme="?light"?\]\s*\{/) ].each do |block|
      assert_equal LIGHT.keys.sort, block.keys.sort
      LIGHT.each { |name, hex| assert_equal hex, block[name], name }
    end
  end

  test "contrast (WCAG 2) holds on both sides: text 4.5:1 on page and card, text on fills 4.5:1, focus / edges 3:1" do
    { "dark" => TOKENS, "light" => LIGHT }.each do |side, t|
      %w[page card].each do |bg|
        %w[ink ink-2 ink-3 accent-ink ok-ink danger].each do |fg|
          assert_operator contrast(t[fg], t[bg]), :>=, 4.5, "#{side}: #{fg} on #{bg}"
        end
        assert_operator contrast(t["accent-soft"], t[bg]), :>=, 3.0, "#{side}: accent-soft on #{bg}"
      end
      %w[accent ok].each { |fill| assert_operator contrast(t["on-accent"], t[fill]), :>=, 4.5, "#{side}: on-accent on #{fill}" }
    end
  end

  # Handoff 0103 -- the 공개 예정 card fades as a whole (opacity on the card: 70% dark, 80% light), so its text is
  # composited with the card over the page; both sides keep 4.5:1.
  def over(fg, bg, alpha)
    f = fg.delete_prefix("#").scan(/../).map { |c| c.to_i(16) }
    b = bg.delete_prefix("#").scan(/../).map { |c| c.to_i(16) }
    "#" + f.zip(b).map { |x, y| format("%02x", (alpha * x + (1 - alpha) * y).round) }.join
  end

  test "the 공개 예정 card's text keeps 4.5:1 through the card's opacity on both sides" do
    card_classes = SeriesThemeHelper::SERIES_THEME[:upcoming_card][1].split
    assert_includes card_classes, "opacity-70"
    assert_includes card_classes, "[[data-theme=light]_&]:opacity-80"
    { "dark" => [ TOKENS, 0.7 ], "light" => [ LIGHT, 0.8 ] }.each do |side, (t, alpha)|
      card = over(t["card"], t["page"], alpha)
      %w[ink ink-2].each do |fg|
        assert_operator contrast(over(t[fg], t["page"], alpha), card), :>=, 4.5, "#{side}: #{fg} on the 공개 예정 card"
      end
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
