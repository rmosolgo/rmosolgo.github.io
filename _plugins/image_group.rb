class ImageGroup < Liquid::Tag
  def initialize(_tagname, text, _tokens)
    @image_paths = text.split(",").map(&:strip)
    pp [self.class, @image_paths, text]
    super
  end
  def render(context)
    "<div class='img-group'>#{@image_paths.map { |path| "<div class='img-container'><a href=\"/assets/images/#{path}\" target=\"_blank\"><img src=\"/assets/images/#{path}\" /></a></div>"}.join}</div>"
  end
end

Liquid::Template.register_tag('imggroup', ImageGroup)
