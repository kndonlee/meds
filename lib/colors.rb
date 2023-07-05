# frozen_string_literal: true

class Colors
  ESCAPE = "\u001b"

  @color_codes = {
  :black => 0,
  :red => 1,
  :green => 2,
  :yellow => 3,
  :blue => 4,
  :purple => 5,
  :cyan => 6,
  :white => 7,
  }

  def self.xterm_color(i)
    "#{ESCAPE}[38;5;#{i}m"
  end

  def self.xterm_color_bg(i)
    "#{ESCAPE}[48;5;#{i}m"
  end
  def self.xterm_bg(i)
    "#{ESCAPE}[#{i}m"
  end

  def self.reset
    "#{ESCAPE}[0m"
  end

  def self.method_missing(name, *args)
    case name.to_s
    when "reset"
      ansi_escape_sequence = reset
    when /^c(\d+)$/
      ansi_escape_sequence = xterm_color($1)
    when /^c(\d+)_bg$/
      ansi_escape_sequence = xterm_color_bg($1)
    when /^(\w+)_bg$/
      i = @color_codes[$1.to_sym]
      if i.nil?
        ansi_escape_sequence = reset
      else
        ansi_escape_sequence = xterm_bg(i.to_i+40)
      end
    when /^(\w+)_bold$/
      i = @color_codes[$1.to_sym]
      if i.nil?
        ansi_escape_sequence = reset
      else
        ansi_escape_sequence = xterm_color(i.to_i+8)
      end
    when /^(\w+)$/
      i = @color_codes[$1.to_sym]
      if i.nil?
        ansi_escape_sequence = reset
      else
        ansi_escape_sequence = xterm_color(i)
      end
    else
      ansi_escape_sequence = reset
    end

    ansi_escape_sequence
  end

  def self.strip_color(str)
    if str.nil?
      ""
    else
      str.gsub(/[\x00-\x1F]\[[0-9;]+m/,'')
    end
  end
end