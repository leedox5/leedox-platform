# Handoff 0063 -- renders a draft text exactly as the customer page will (same
# ContentMarkdown, same image rules), so an editor can check it before saving.
# It reports what was left out (an external image, an image that is not this
# record's). Admin-only through Admin::BaseController; nothing is stored.
class Admin::MarkdownPreviewsController < Admin::BaseController
  MAX_CHARS = 200_000

  def create
    parent, profile = find_parent
    result = ContentMarkdown.render_with_warnings(params[:text].to_s.first(MAX_CHARS), parent: parent, profile: profile, admin: true)
    render partial: "admin/markdown_previews/preview", locals: { result: result }, layout: false
  end

  private

  # An unsaved record has no id yet, so it has no images to resolve.
  def find_parent
    case params[:parent_type]
    when "product_line" then [ ProductLine.find_by(id: params[:parent_id]), :marketing ]
    else [ ContentEpisode.find_by(id: params[:parent_id]), :episode ]
    end
  end
end
