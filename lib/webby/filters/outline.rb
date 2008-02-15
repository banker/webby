# $Id$

require 'hpricot'

module Webby
module Filters

# The Outline filter is used to insert outline numbering into HTML heading
# tags (h1, h2, h3, etc.) and to generate a table of contents based on the
# heading tags. The table of contents is inserted into the page at the
# location of the <toc /> tag. If there is no <toc /> tag, then a table of
# contents will not be created but outline numbering will still take place.
#
# If a table of contents is desired without outline number being inserted
# into the heading tags, this can be specified in the attibutes of the
# <toc /> tag itself.
#
#    <toc outline_numbering="off" />
#
# This will generate a table of contents, but not insert outline numbering
# into the heading tags.
#
# The Outline filter will only work on valid HTML or XHTML pages. Therefore
# it should be used after any markup langauge filters (textile, markdown,
# etc.).
#
class Outline
  include ERB::Util

  class Error < StandardError; end    # :nodoc:

  # TODO: options for table of contents
  #       - where to start numbering
  #       - list style (numbered or unordered)
  #       - header range to select (h2-h3)

  # call-seq:
  #    Outline.new( html )
  #
  # Creates a new outline filter that will operate on the given
  # _html_ string.
  #
  def initialize( str )
    @str = str

    @cur_level, @base_level, @cur_depth = nil
    @level = [0] * 6
    @h_rgxp = %r/^h(\d)$/o
    @toc = []
    @outline_numbering = true
  end

  # call-seq:
  #    filter    => html
  #
  # Process the original html document passed to the filter when it was
  # created. The document will be scanned for heading tags (h1, h2, etc.)
  # and outline numbering and id attributes will be inserted. A table of
  # contents will also be created and inserted into the page if a <toc />
  # tag is found.
  #
  # For example, if there is a heading tag
  #
  #    <h3>Get Fuzzy</h3>
  #
  # somewhere in a page about comic strips, the tag might be altered as such
  #
  #    <h3 id="h2_2_1"><span class="heading-num>2.2.1</span>Get Fuzzy</h3>
  # 
  # The id attribute is used to generate a linke from the table of contents
  # to this particular heading tag. The original text of the tag is used in
  # the table of contents -- "Get Fuzzy" in this example.
  #
  def filter
    doc = Hpricot(@str)

    # extract directives from the "toc" tag
    toc_elem = doc.search('toc').first

    unless toc_elem.nil?
      @outline_numbering = toc_elem['outline_numbering'] !~ %r/off/i
      @list_style = toc_elem['list'] || 'ol'
    end

    doc.traverse_element(*%w[h1 h2 h3 h4 h5 h6]) do |elem|
      text, id = heading_info(elem)
      add_to_toc(text, id)
    end

    # create the TOC ordered list

    toc_elem.swap(toc) unless toc_elem.nil?
    
    # replace the "toc" tag with the ordered list

    doc.to_html
  end


  private

  # Returns information for the given heading element. The information is
  # returned as a two element array: [text, id].
  #
  # This method will also insert outline numbering and an id attribute. The
  # outline numbering can be disabled, but the id attribute must be present
  # for TOC generation.
  #
  def heading_info( elem )
    m = @h_rgxp.match(elem.name)
    level = Integer(m[1])

    self.current_level = level
    text = elem.inner_text

    lbl = label
    if outline_numbering?
      elem.children.first.before {tag!(:span, lbl, :class => 'heading-num')}
    end
    elem['id'] = "h#{lbl.tr('.','_')}" if elem['id'].nil?

    return [text, elem['id']]
  end

  # Set the current heading level. This will set the label and depth as
  # well. An error will be raised if the _level_ is less than the base
  # heading level.
  #
  # The base heading level will be set to the _level_ if it has not already
  # been set. Therefore, the first heading tag encountered defines the base
  # heading level.
  #
  def current_level=( level )
    @base_level ||= level
    @cur_level ||= level

    if level < @base_level
      raise Error, "heading tags are not in order, cannot outline"
    end

    if level == @cur_level
      @level[level-1] += 1
    elsif level > @cur_level
      @cur_level.upto(level-1) {|ii| @level[ii] += 1}
    else
      @cur_level.downto(level+1) {|ii| @level[ii-1] = 0}
      @level[level-1] += 1
    end

    @cur_level = level
  end

  # Return the label string for the current heading level.
  #
  def label
    rv = @level.dup
    rv.delete(0)
    rv.join('.')
  end

  # Return the nesting depth of the current heading level with respect to the
  # base heading level. This is a one-based number.
  #
  def depth
    @cur_level - @base_level + 1
  end

  # Add the given text and id reference to the table of contents.
  #
  def add_to_toc( text, id )
    a = "<a href=\"##{id}\">#{h(text)}</a>"
    @toc << [depth, a]
  end

  # Returns the table of contents as a collection of nested ordered lists.
  # This is fully formatted HTML.
  #
  def toc
    ary = []

    lopen = "<#@list_style>"
    lclose = "</#@list_style>"
    prev_depth = open = 0

    @toc.each do |a|
      cur = a.first

      # close out the previous list item if we're at the same level
      if cur == prev_depth
        ary << "</li>"

      # if we are increasing the level, then start a new list
      elsif cur > prev_depth
        ary << lopen
        open += 1

      # we are decreasing the level; close out tags but ensure we don't
      # close out all the tags (leave one open)
      else
        (prev_depth - cur).times {
          ary << "</li>" << lclose
          open -= 1
          break if open <= 0
        }
        if open > 0
          ary << "</li>"
        else
          ary << lopen
          open += 1
        end
      end

      # add the current element
      ary << "<li>" << a.last
      prev_depth = cur
    end

    # close out the remaingling tags
    ary << "</li>" << lclose
    ary.join("\n")
  end

  # Returns +true+ if outline numbering should be inserted into the heading
  # tags. Returns +false+ otherwise.
  #
  def outline_numbering?
    @outline_numbering
  end
end  # class Outline

# Generate a outline numbering and/or a table of contents in the input HTML
# text.
#
register :outline do |input|
  Outline.new(input).filter
end

end  # module Filters
end  # module Webby

# EOF