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
end
