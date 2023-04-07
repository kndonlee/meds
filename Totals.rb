#!/usr/bin/env ruby

$LOAD_PATH.unshift File.dirname(__FILE__)

require 'curses'
require 'meds'

class TotalFilesApp
  def initialize
    @dir_path = "./totals"
    @files = Dir.children(@dir_path).sort
    @current_file_index = 0

    @meds_dash = MedDash.new
  end

  def run
    Curses.init_screen
    Curses.start_color
    Curses.noecho
    Curses.curs_set(0)
    Curses.start_color
    Curses.attron(A_NORMAL)
    @win = Curses::Window.new(0, 0, 1, 2)
    main_loop
  ensure
    Curses.close_screen
  end

  private

  def main_loop
    loop do
      display_dash
      # handle_input
      sleep(15)
    end
  end

  def display_dash
    Curses.clear
    Curses.setpos(0, 0)
    #Curses.addstr(Colors.strip_color(@meds_dash.dash))
    Curses.addstr(@meds_dash.dash)
    Curses.refresh
  end

  def display_current_file
    Curses.clear
    @win.setpos(0, 0)
    current_file_path = File.join(@dir_path, @files[@current_file_index])
    file_content = File.read(current_file_path)
    Curses.setpos(0, 0)
    Curses.addstr(file_content)
    Curses.refresh
  end

  # def handle_input
  #   case Curses.getch
  #   when Curses::Key::LEFT
  #     @current_file_index -= 1 unless @current_file_index.zero?
  #   when Curses::Key::RIGHT
  #     @current_file_index += 1 unless @current_file_index == @files.length - 1
  #   when 'q'.ord, Curses::Key::ESC
  #     exit(0)
  #   end
  # end
end

TotalFilesApp.new.run
