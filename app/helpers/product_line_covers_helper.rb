module ProductLineCoversHelper
  # URL of a ProductLine cover variant. `v` is the original blob's id so a
  # replaced image gets a new URL and browser-cached copies are bypassed.
  def product_line_cover_src(product_line, variant, admin: false)
    version = product_line.cover_image.blob.id
    if admin
      admin_product_line_cover_image_path(product_line, variant, v: version)
    else
      product_cover_path(product_line.slug, variant, v: version)
    end
  end
end
