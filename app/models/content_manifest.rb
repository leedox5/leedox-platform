# Chapter content ships as plain files under hq/ (see script/sync_curriculum.sh),
# committed to this repo's git history like any other file. Deploys (Railway)
# get that content via a fresh `git` checkout of the pushed commit, and git does
# not store per-file modification times -- checkout always stamps every file
# with "now" (the checkout/build time), identically across the whole tree. That
# makes File.mtime unusable in production for "last updated" display: two
# chapters committed 47 minutes apart at HQ show as the exact same time once
# deployed, because that's genuinely when the deploy's checkout wrote them to
# disk, not when their content was last authored (see
# leedox_last_updated_timestamp_fix_r1 -- reproduced locally by diffing a fresh
# `git clone` of this repo against the working tree's restore_mtimes()-stamped
# mtimes).
#
# sync_curriculum.sh's restore_mtimes() already computes each file's true last
# commit date from HQ's git history; it now also writes that out as
# .last_updated.json alongside the content itself. Because that manifest is
# real file *content* (not filesystem metadata), git preserves it exactly
# across any checkout, so reading it here is unaffected by where/when the app
# was deployed.
class ContentManifest
  def self.last_updated_at(directory, slug)
    value = load(directory)["#{slug}.md"]
    return Time.iso8601(value).in_time_zone if value

    # Manifest missing this entry (e.g. sync_curriculum.sh hasn't been run
    # since the file was added) -- fall back to the filesystem's mtime rather
    # than blow up on a decorative timestamp. Still zone-converted, so this
    # fallback alone fixes the display bug even without a manifest.
    File.mtime(directory.join("#{slug}.md")).in_time_zone
  end

  def self.load(directory)
    manifest_path = directory.join(".last_updated.json")
    return {} unless File.exist?(manifest_path)

    JSON.parse(File.read(manifest_path))
  end
end
