# -*- coding: utf-8 -*-
require 'kramdown'
require 'coderay'

module RedmineMarkdownExtraFormatter
  class WikiFormatter
    def initialize(text)
      @text = text
    end

    def to_html(&block)
      @macros_runner = block
      parsedText = Kramdown::Document.new(@text).to_html
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
