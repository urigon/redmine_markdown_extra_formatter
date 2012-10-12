# -*- coding: utf-8 -*-
require 'bluefeather'
require 'coderay'

module BlueFeather
  class Parser

    # derived from bluefeather.rb

    TOCRegexp = %r{
      ^\{    # bracket on line-head
      [ ]*    # optional inner space
      ([<>])?
      toc

      (?:
        (?:
          [:]    # colon
          |      # or
          [ ]+   # 1 or more space
        )
        (.+?)    # $1 = parameter
      )?

      [ ]*    # optional inner space
      \}     # closer
      [ ]*$   # optional space on line-foot
    }ix

    TOCStartLevelRegexp = %r{
      ^
      (?:              # optional start
        h
        ([1-6])        # $1 = start level
      )?

      (?:              # range symbol
        [.]{2,}|[-]    # .. or -
      )

      (?:              # optional end
        h?             # optional 'h'
        ([1-6])        # $2 = end level
      )?$
    }ix

    ### Transform any Markdown-style horizontal rules in a copy of the specified
    ### +str+ and return it.
    def transform_toc( str, rs )
      @log.debug " Transforming tables of contents"
      str.gsub(TOCRegexp){
        start_level = 1 # default
        end_level = 6

        param = $2
        if param then
          if param =~ TOCStartLevelRegexp then
            if !($1) and !($2) then
              rs.warnings << "illegal TOC parameter - #{param} (valid example: 'h2..h4')"
            else
              start_level = ($1 ? $1.to_i : 1)
              end_level = ($2 ? $2.to_i : 6)
            end
          else
            rs.warnings << "illegal TOC parameter - #{param} (valid example: 'h2..h4')"
          end
        end

        if rs.headers.first and rs.headers.first.level >= (start_level + 1) then
          rs.warnings << "illegal structure of headers - h#{start_level} should be set before h#{rs.headers.first.level}"
        end


        ul_text = "\n\n"
        div_class = 'toc'
        div_class << ' right' if $1 == '>'
        div_class << ' left' if $1 == '<'
        ul_text << "<ul class=\"#{div_class}\">"
        rs.headers.each do |header|
          if header.level >= start_level and header.level <= end_level then
            ul_text << "<li class=\"heading#{header.level}\"><a href=\"##{header.id}\">#{header.content_html}</a></li>\n"
          end
        end
        ul_text << "</ul>"
        ul_text << "\n"

        ul_text # output

      }
    end
  end
end

module RedmineMarkdownExtraFormatter
  class WikiFormatter
    def initialize(text)
      @text = text
    end

    def to_html(&block)
      @macros_runner = block
      parsedText = BlueFeather.parse(@text)
      parsedText = inline_macros(parsedText)
      parsedText = syntax_highlight(parsedText)
    rescue => e
      return("<pre>problem parsing wiki text: #{e.message}\n"+
             "original text: \n"+
             @text+
             "</pre>")
    end

    MACROS_RE = /
          (!)?                        # escaping
          (
          \{\{                        # opening tag
          ([\w]+)                     # macro name
          (\(([^\}]*)\))?             # optional arguments
          \}\}                        # closing tag
          )
        /x

    def inline_macros(text)
      text.gsub!(MACROS_RE) do
        esc, all, macro = $1, $2, $3.downcase
        args = ($5 || '').split(',').each(&:strip)
        if esc.nil?
          begin
            @macros_runner.call(macro, args)
          rescue => e
            "<div class=\"flash error\">Error executing the <strong>#{macro}</strong> macro (#{e})</div>"
          end || all
        else
          all
        end
      end
      text
    end

    PreCodeClassBlockRegexp = %r{^<pre><code\s+class="(\w+)">\s*\n*(.+?)</code></pre>}m

    def syntax_highlight(str)
      str.gsub(PreCodeClassBlockRegexp) {|block|
        syntax = $1.downcase
        "<pre><code class=\"#{syntax.downcase} syntaxhl\">" +
        CodeRay.scan($2, syntax).html(:escape => true, :line_numbers => nil) +
        "</code></pre>"
      }
    end

    def get_section(index)
      section = extract_sections(index)[1]
      hash = Digest::MD5.hexdigest(section)
      return section, hash
    end

    def update_section(index, update, hash=nil)
      t = extract_sections(index)
      if hash.present? && hash != Digest::MD5.hexdigest(t[1])
        raise Redmine::WikiFormatting::StaleSectionError
      end
      t[1] = update unless t[1].blank?
      t.reject(&:blank?).join "\n\n"
    end

    private

    def extract_sections(index)
      selected, before, after = [[],[],[]]
      pre = :none
      state = 'before'

      selected_level = 0
      header_count = 0

      @text.each_line do |line|

        if line =~ /^(~~~|```)/
          pre = pre == :pre ? :none : :pre
        elsif pre == :none
          
          level = if line =~ /^(#+)/
                    $1.length
                  elsif line.strip =~ /^=+$/ 
                    line = eval(state).pop + line
                    1
                  elsif line.strip =~ /^-+$/ 
                    line = eval(state).pop + line
                    2
                  else
                    nil
                  end
          unless level.nil?
            if level <= 4
              header_count += 1
              if state == 'selected' and selected_level >= level
                state = 'after'
              elsif header_count == index
                state = 'selected'
                selected_level = level
              end
            end
          end
        end

        eval("#{state} << line")
      end

      [before, selected, after].map{|x| x.join.strip}
    end

  end
end
