# frozen_string_literal: true

class ANSI
  ESCAPE = "\u001b"
  def self.start_alternate_buffer
    "#{ESCAPE}[?1049h"
  end

  def self.end_alternative_buffer
    "#{ESCAPE}[?1049l"
  end

  def self.hide_cursor
    "#{ESCAPE}[?25l"
  end

  def self.show_cursor
    "#{ESCAPE}[?25h"
  end

  def self.move_cursor(row, column)
    # row & column are 1-indexed
    print "#{ESCAPE}[#{row.to_s};#{column.to_s}H"
  end

  def self.clear
    "#{ESCAPE}[2J"
  end

  def self.clear_line
    "#{ESCAPE}[2K\r"
  end

  def self.clear_line_right
    "#{ESCAPE}[0K"
  end

  def self.clear_line_left
    "#{ESCAPE}[1K"
  end

end
