module ApplicationHelper

  def markdown(text)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML,
                                       no_intra_emphasis: true,
                                       fenced_code_blocks: true,
                                       disable_indented_code_blocks: true,
                                       tables: true,
                                       underline: true,
                                       highlight: true
                                      )
    return markdown.render(text).html_safe
  end

  def edit_content_path(locale)
    url_for(controller: :content_edition, action: :edit, edit_locale: locale)
  end

  def preview_draft_path(locale)
  end

  def discard_draft_path(locale)
    url_for(controller: :content_edition, action: :discard_draft, edit_locale: locale)
  end

  def publish_draft_path(locale)
    url_for(controller: :content_edition, action: :publish_draft, edit_locale: locale)
  end

  def custom_colors
    colors = {}

    if ENV['PRIMARY_COLOR'].present?
      colors['primary'] = ENV['PRIMARY_COLOR']
      colors['primary-light'] = "\#{lighten(#{ENV['PRIMARY_COLOR']}, 3%)}"
      colors['primary-light2'] = "\#{lighten(#{ENV['PRIMARY_COLOR']}, 45%)}"
    end

    if ENV['TOPNAV_BACKGROUND_COLOR'].present?
      colors['topnav_background'] = ENV['TOPNAV_BACKGROUND_COLOR']
    end

    colors
  end
end
