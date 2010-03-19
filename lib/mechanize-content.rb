require 'rubygems'
require 'mechanize'
require 'image_size'
require 'open-uri'

class MechanizeContent
  
  attr_accessor :urls
  
  MIN_WIDTH  = 64
  MIN_HEIGHT = 64
  
  def initialize(*args)
    @urls = *args
  end
  
  def best_title
    @best_title || fetch_titles
  end
  
  def best_text
    @best_text || fetch_texts
  end
  
  def best_image
    @best_image || fetch_images
  end
  
  def fetch_images
    (@pages || fetch_pages).each do |page|
      image = fetch_image(page)
      return @best_image = image unless image.nil?
    end
    return nil
  end
  
  def fetch_texts
    (@pages || fetch_pages).each do |page|
      text = fetch_text(page)
      return @best_text = text unless text.nil?
    end
    return nil
  end
  
  def fetch_titles
    (@pages || fetch_pages).each do |page|
      title = page.title
      unless title.nil?
        ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
        title = ic.iconv(title + ' ')[0..-2]
        return @best_title = title
      end
      
    end
    return @urls.first
  end
  
  def fetch_pages
    @pages = []
    @urls.each do |url|
      page = fetch_page(url)
      @pages << page unless page.nil?
    end
    @pages
  end
  
  def fetch_page(url)
    begin
      page = (@agent || init_agent).get(url)
      if page.class ==  Mechanize::Page
        return page
      else
        return nil
      end
    rescue Timeout::Error
      puts "Timeout - "+url
    rescue Errno::ECONNRESET
      puts "Connection reset by peer - "+url
    rescue Mechanize::ResponseCodeError
      puts "Invalid url"
    rescue Mechanize::UnsupportedSchemeError
      puts "Unsupported Scheme"
    rescue
      puts "There was a problem connecting - "+url
    end
  end
  
  def init_agent
    agent = Mechanize.new
    agent.user_agent_alias = 'Mac Safari'
    return @agent = agent
  end
  
  def fetch_text(page)
    top_content = fetch_content(page)
    if top_content
      text = top_content.text.delete("\t").delete("\n").strip
      ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
      text = ic.iconv(text + ' ')[0..-2]
    else
      return nil
    end
  end
  
  def fetch_content(page)
    doc = page.parser
    readability = {}
    doc.css('p').each do |paragraph|
      if readability[paragraph.parent].nil?
        readability[paragraph.parent] = 0
      end
      parent_class = paragraph.parent['class'] || ""
      parent_id = paragraph.parent['id'] || ""
      if !parent_class.match('(comment|meta|footer|footnote)').nil?
        readability[paragraph.parent] -= 50
      elsif !parent_class.match('((^|\\s)(post|hentry|entry[-]?(content|text|body)?|article[-_]?(content|text|body)?)(\\s|$))').nil?
        readability[paragraph.parent] += 25
      end
    
      if !parent_id.match('(comment|meta|footer|footnote)').nil?
        readability[paragraph.parent] -= 50
      elsif !parent_id.match('((^|\\s)(post|hentry|entry[-]?(content|text|body)?|article[-_]?(content|text|body)?)(\\s|$))').nil?
        readability[paragraph.parent] += 25
      end
    
      if paragraph.inner_text().length > 10
        readability[paragraph.parent] += 1
      end
      readability[paragraph.parent] += paragraph.inner_text().count(',')
    end
    sorted_results = readability.sort_by { |parent,score| -score }
    if sorted_results.nil? || sorted_results.first.nil?
      return nil
    else
      top_result = sorted_results.first.first
      top_result.css('script').unlink
      top_result.css('iframe').unlink
      top_result.css('h1').unlink
      top_result.css('h2').unlink
      return top_result
    end
  end
  
  def get_base_url(doc, url)
    base_url = doc.xpath("//base/@href").first
    if base_url.nil?
      return url
    else
      return base_url.value
    end
  end
  
  def fetch_image(page)
    top_content = fetch_content(page)
    if top_content
      return find_best_image(top_content.css('img'), get_base_url(page.parser, page.uri))
    else
      return nil
    end
  end  
  
  def valid_image?(width, height, src)
    if width > MIN_WIDTH && height > MIN_HEIGHT && !src.include?("banner") && !src.include?(".gif")
      if (!(width == 728) && !(height == 90))
        return true
      end
    end
    return false
  end
  
  def build_absolute_url(current_src, url)
    uri = URI.parse(current_src)
    if uri.relative?
      current_src = (URI.parse(url.to_s)+current_src).to_s
    end
    current_src
  end
  
  def find_best_image(all_images, url)
    begin
      current_src = nil
      all_images.each do |img|
        current_src = img["src"]
        if valid_image?(img['width'].to_i, img['height'].to_i, current_src)
          return build_absolute_url(current_src, url)
        end
      end
      all_images.each do |img|
        current_src = img["src"]
        current_src = build_absolute_url(current_src, url)
        open(current_src, "rb") do |fh|
          is = ImageSize.new(fh.read)
          if valid_image?(is.width, is.height, current_src)
            return current_src
          end
        end
      end
      return nil
    rescue Errno::ENOENT
      puts "No such file - " + current_src
    rescue 
      puts "There was a problem connecting - " + current_src
    end
  end
  
end