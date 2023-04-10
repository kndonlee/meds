#!/usr/bin/env ruby

require 'date'
require 'sqlite3'
require 'io/wait'
require 'io/console'
require 'json'

APP_PATH = File.dirname(__FILE__)
$LOAD_PATH.unshift APP_PATH

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
    str.gsub(/[\x00-\x1F]\[[0-9;]+m/,'')
  end
end

class Updater
  attr_reader :current_sha
  def initialize
    @current_sha = `git rev-parse HEAD`
    @update_interval = 60
    @last_dash_update = Time.now.to_i
  end

  def updated?
    now = Time.now.to_i
    if (now - @last_dash_update) > @update_interval
      `git pull 2>&1 > /dev/null`
      @last_dash_update = now
      new_sha = `git rev-parse HEAD`
      return new_sha != @current_sha
    end

    return false
  end
end

class IMessageChatDB

  #@@query_history = 4 * 86400
  @@query_history = 86400 * 2
  @@reset_time= 5

  def initialize
    @db_path = "#{ENV['HOME']}/Library/Messages/chat.db"

    unless File.readable?(@db_path)
      raise "status=ERROR error=FILE_READ file=#{@db_path}"
    end
  end

  def chat_id
    app_path = File.dirname($PROGRAM_NAME)

    chat_id_path = "#{app_path}/chatid"
    if File.readable?(chat_id_path)
      File.read(chat_id_path).strip
    else
      # donalds chatid
      "chat574232935236064109"
    end
  end

  def db_query
    @query || (@query = "
    SELECT
      message.is_from_me,
      chat.chat_identifier,
      datetime (message.date / 1000000000 + strftime (\"%s\", \"2001-01-01\"), \"unixepoch\", \"localtime\") AS message_date,
      message.date / 1000000000 + strftime (\"%s\", \"2001-01-01\") AS message_epoch,
      strftime (\"%s\", \"now\") AS now_epoch,
      message.text,
      message.attributedBody
    FROM
      chat
      JOIN chat_message_join ON chat. \"ROWID\" = chat_message_join.chat_id
      JOIN message ON chat_message_join.message_id = message. \"ROWID\"
    WHERE
       chat.chat_identifier LIKE \"#{chat_id}\"
       AND (now_epoch-message_epoch) <= #{@@query_history}
    ORDER BY
      message_date ASC")
  end

  def get
    @db = SQLite3::Database.new(@db_path)
    db_results = @db.execute(db_query)

    db_results_parsed = db_results.map do |result|

      if result[5] != nil
        result[6] = nil
        result
      elsif result[6].nil?
        result
      else
        attributed_body = result[6].force_encoding('UTF-8').encode('UTF-8', :invalid => :replace)

        #puts "unicodebody: #{attributed_body}"

        if attributed_body.include?("NSNumber")
          attributed_body = attributed_body.split("NSNumber")[0]
          if attributed_body.include?("NSString")
            attributed_body = attributed_body.split("NSString")[1]
            if attributed_body.include?("NSDictionary")
              attributed_body = attributed_body.split("NSDictionary")[0]
              attributed_body = attributed_body[6..-13]

              if attributed_body =~ /^.[\u0000]/
                result[5] = attributed_body.gsub(/^.[\u0000]/,'')
              else
                result[5] = attributed_body
              end

              result[6] = nil
              result
            end
          end
        end
      end
    end

    @db.close

    db_results_parsed.compact
  end

  def pretty_print
    pp get
  end

  def to_s
    str = ""
    get.map do |r|
      str += "========\n#{r[5]}\n"
    end
    str
  end
end

class Med
  class Dose
    attr_accessor :epoch_time, :dose, :dose_units
    def initialize(epoch_time:, dose:, dose_units:)
      @epoch_time = epoch_time
      @dose_units = dose_units
      @dose = dose.to_f
    end

    def yesterday?
      @epoch_time > Med.last_5am_epoch_yesterday && @epoch_time < Med.last_5am_epoch
    end

    def to_s
      yesterday = yesterday? ? "#{Colors.c72} [Y]#{Colors.reset}" : ""
      t = Med.epoch_to_time_sc(epoch_time)
      "#{t} #{Colors.c183}#{dose} #{Colors.blue_bold}#{dose_units}#{Colors.reset}#{yesterday}"
    end
  end

  attr_reader :emoji, :dose_units
  def initialize(name:, interval:, required:true, default_dose:, max_dose:0, dose_units:, emoji:)
    @name = name
    @interval = interval
    @required = required
    @default_dose = default_dose
    @dose_units = dose_units
    @max_dose = max_dose

    @dose_log = []
    @emoji = [emoji.hex].pack("U") # convert to unicode emoji
  end

  def normalize_dose(dose, dose_units)
    if dose.to_s.include?("/")
      n, d = dose.split('/').map(&:to_i)
      normalized_dose = n.to_f / d
    else
      normalized_dose = dose.to_f
    end

    if dose_units.to_s.downcase == @dose_units.to_s
      normalized_dose
    elsif dose_units.to_s.strip.empty?
      normalized_dose
    elsif @dose_units.to_s.downcase == "mg" && dose_units.to_s.downcase == "g"
      normalized_dose = normalized_dose * 1000
    elsif @dose_units.to_s.downcase == "g" && dose_units.to_s.downcase == "mg"
      normalized_dose = normalized_dose.to_f / 1000
    else
      puts "#{@name} unable to normalize dose from #{dose} #{dose_units} to #{@dose_units}"
    end

    normalized_dose
  end

  def log(epoch_time:, dose:nil, units:nil)
    dose = dose.nil? ? @default_dose : dose
    dose = normalize_dose(dose, units)

    @dose_log.push(
      Dose.new(
        epoch_time: epoch_time,
        dose: dose,
        dose_units: @dose_units,
      )
    )
  end

  def elapsed
    if last_dose.nil?
      86400
    else
      (Time.now.to_i - last_dose).abs
    end
  end

  def elapsed_to_s
    elapsed_s = elapsed

    if elapsed_s == 0
      "00:00"
    else
      elapsed_hours = sprintf("%02d", (elapsed_s / 3600).to_i)
      elapsed_minutes = sprintf("%02d", ((elapsed_s % 3600) / 60).to_i)

      "#{elapsed_hours}:#{elapsed_minutes}"
    end
  end

  def last_dose
    if @dose_log.last.nil?
      nil
    else
      @dose_log.select{|d| d.dose > 0}.last.epoch_time
    end
  end

  def total_dose_yesterday
    @dose_log.select { |dose| dose.epoch_time > Med.last_5am_epoch_yesterday && dose.epoch_time < Med.last_5am_epoch}.map(&:dose).sum
  end

  def total_dose
    @dose_log.select { |dose| dose.epoch_time > Med.last_5am_epoch}.map(&:dose).sum
  end

  def self.last_5am_epoch_yesterday
    last_5am_epoch - 86400
  end

  def self.last_5am_epoch
    now = Time.now
    today_5am = Time.new(now.year, now.month, now.day, 5, 0, 0)

    if now < today_5am
      # if it's before 5am today, go back to yesterday at 5am
      yesterday_5am = today_5am - 24 * 60 * 60
      return yesterday_5am.to_i
    else
      return today_5am.to_i
    end
  end

  def optl_s
    "#{Colors.c67_bg}#{Colors.c184}Optl#{Colors.reset}"
  end

  def take_s
    "#{Colors.red}TAKE#{Colors.reset}"
  end

  def wait_s
    "#{Colors.c10}wait#{Colors.reset}"
  end

  def done_s
    "#{Colors.c154}done#{Colors.reset}"
  end

  def optional?
    elapsed > (@interval * 3600) && elapsed < (@required * 3600)
  end

  def due?
    elapsed > (@required * 3600)
  end

  def wait?
    elapsed < (@interval * 3600)
  end

  def done?
    total_dose >= @max_dose && @max_dose != 0
  end

  def due_to_s
    if done?
      done_s
    elsif optional?
      optl_s
    elsif due?
      take_s
    elsif wait?
      wait_s
    else
      optl_s
    end
  end

  def self.epoch_to_time_s(e)
    Time.at(e).strftime("%I:%M%P")
  end

  def self.epoch_to_time_sc(e)
    time, meridien = Time.at(e).strftime("%I:%M %P").split(" ")
    if meridien.include?("am")
      #"#{Colors.c178}#{time}#{Colors.c208}#{meridien}#{Colors.reset}"
      "#{Colors.c208}#{time}#{Colors.c210}#{meridien} #{Colors.reset}"
    else
      "#{Colors.purple}#{time}#{Colors.c169}#{meridien} #{Colors.reset}"
    end
  end

  def last_dose_s
    if last_dose.nil?
      "#{Colors.cyan}NA      #{Colors.reset}"
    else
      Med.epoch_to_time_sc(last_dose)
    end
  end

  # Summarize
  def list_yesterday_to_s
    yesterday_doses = @dose_log.select { |dose| dose.epoch_time > Med.last_5am_epoch_yesterday && dose.epoch_time < Med.last_5am_epoch}

    return "" if yesterday_doses.empty?
    #puts yesterday_doses.first.epoch_time
    date = Time.at(yesterday_doses.first.epoch_time).strftime("%m/%d");
    s = ""
    yesterday_counts = yesterday_doses.group_by(&:dose).transform_values(&:count)
    yesterday_counts.each do |dose, count|
      s += "#{Colors.c72}#{sprintf("%-8s",date + " " + count.to_s + "x")} #{Colors.c183}#{dose} #{Colors.blue_bold}#{@dose_units}#{Colors.reset}\n"
    end
    s
  end

  def list_to_s
    s = ""
    @dose_log.select {|d| d.epoch_time > Med.last_5am_epoch}.each do |d|
      s += "#{d.to_s}\n"
    end
    s
  end

  def color_hrs
    "#{Colors.blue_bold}h#{Colors.reset}"
  end

  def color_elapsed
    e = elapsed_to_s
    if e =~ /^00:/
      "#{Colors.c70}#{elapsed_to_s}#{Colors.reset}"
    elsif e =~ /^0[12]:/
      "#{Colors.c71}#{elapsed_to_s}#{Colors.reset}"
    elsif e =~ /^0[345]:/
      "#{Colors.c72}#{elapsed_to_s}#{Colors.reset}"
    elsif e =~ /^0[6789]:/
      "#{Colors.c73}#{elapsed_to_s}#{Colors.reset}"
    elsif e =~ /^1.:/
      "#{Colors.c74}#{elapsed_to_s}#{Colors.reset}"
    else #20 hrs and beyond
      "#{Colors.c75}#{elapsed_to_s}#{Colors.reset}"
    end
  end

  def to_s
    interval = sprintf("%2d", @interval)
    required_formatted = sprintf("%2d", @required)
    dose = sprintf("%6.1f", total_dose)
    dose_y = sprintf("%6.1f", total_dose_yesterday)

    last = "Last:#{last_dose_s}"
    elapsed = "Elapsed:#{color_elapsed}"
    due = "Due:#{due_to_s}"
    every = "Every:#{Colors.cyan}#{interval}#{color_hrs}"
    required = "Required:#{Colors.cyan}#{required_formatted}#{color_hrs}"
    total = "Total:#{Colors.purple_bold}#{dose}#{Colors.blue_bold} #{sprintf("%-04s",@dose_units)}#{Colors.reset}"
    total_yesterday = "Yesterday:#{Colors.purple_bold}#{dose_y}#{Colors.blue_bold} #{sprintf("%-04s",@dose_units)}#{Colors.reset}"

    "#{last}  #{elapsed}  #{due}  #{every}  #{required}  #{total} #{total_yesterday}"
  end
end

class MedDash
  @@emoji_ranges = [
    0x1F600..0x1F64F, # Emoticons
    0x1F300..0x1F5FF, # Misc Symbols and Pictographs
    0x1F680..0x1F6FF, # Transport and Map
    0x2600..0x26FF,   # Misc symbols
    0x2700..0x27BF,   # Dingbats
    0xFE00..0xFE0F,   # Variation Selectors
    0x1F900..0x1F9FF, # Supplemental Symbols and Pictographs
    0x1F1E6..0x1F1FF  # Regional indicators
  ]


  @@emoji_regex = /[\u{1F600}-\u{1F64F}\u{2702}-\u{27B0}\u{1F680}-\u{1F6FF}\u{1F300}-\u{1F5FF}\u{1F1E6}-\u{1F1FF}]/

  attr_accessor :meds
  def initialize
    @version = "2.1.8"
    @hostname = `hostname`.strip
    reset_meds

    @updater = Updater.new
    @last_dash_update = Time.now.to_i
    @last_totals_update = Time.now.to_i
    @mode = "d"
    @display_dash = true
    @display_totals = true
    @save_totals = false
  end

  def last_update_time
    Time.now.strftime("%a %Y-%m-%d %I:%M:%S%P")
  end

  def dashboard_header
    "#{Colors.yellow_bold}Last Update:#{Colors.purple_bold}#{last_update_time}  #{Colors.yellow_bold}Version:#{Colors.purple_bold}#{@version}  #{Colors.yellow_bold}Host:#{Colors.purple_bold}#{@hostname} #{Colors.c47}[D]ash [T]otals#{Colors.reset}"
  end

  def log_header
    "#{Colors.yellow_bold}Log#{Colors.reset}"
  end

  def reset_meds
    # required == interval => TAKE
    # required >  interval => Optl to TAKE
    #
    @meds = {}
    @meds[:morphine]    = Med.new(name: :morphine,    interval:8,  required:8,  default_dose:15,   max_dose:0,    dose_units: :mg,   emoji:"1F480")
    @meds[:morphine_bt] = Med.new(name: :morphine_bt, interval:8,  required:48, default_dose:7.5,  max_dose:0,    dose_units: :mg,   emoji:"1F48A")
    @meds[:baclofen]    = Med.new(name: :baclofen,    interval:4,  required:6,  default_dose:7.5,  max_dose:0,    dose_units: :mg,   emoji:"26A1")
    @meds[:esgic]       = Med.new(name: :esgic,       interval:4,  required:24, default_dose:1,    max_dose:0,    dose_units: :unit, emoji:"1F915")
    @meds[:lyrica]      = Med.new(name: :lyrica,      interval:12, required:12, default_dose:150,  max_dose:300,  dose_units: :mg,   emoji:"1F9E0")
    @meds[:xanax]       = Med.new(name: :xanax,       interval:12, required:12, default_dose:0.25, max_dose:0.25, dose_units: :mg,   emoji:"1F630")

    @meds[:taurine]     = Med.new(name: :taurine,     interval:3,  required:5,  default_dose:500,  max_dose:0,    dose_units: :mg,   emoji:"1F48A")
    @meds[:calcium]     = Med.new(name: :calcium,     interval:3,  required:5,  default_dose:250,  max_dose:2000, dose_units: :mg,   emoji:"1F9B4")
    @meds[:msm]         = Med.new(name: :msm,         interval:3,  required:5,  default_dose:500,  max_dose:2000, dose_units: :mg,   emoji:"26FD")
    @meds[:iron]        = Med.new(name: :iron,        interval:3,  required:5,  default_dose:10.5, max_dose:52.5, dose_units: :mg,   emoji:"1FA78")
    @meds[:magnesium]   = Med.new(name: :magnesium,   interval:6,  required:6,  default_dose:48,   max_dose:0,    dose_units: :mg,   emoji:"1F48A")
    @meds[:nac]         = Med.new(name: :nac,         interval:24, required:24, default_dose:600,  max_dose:0,    dose_units: :mg,   emoji:"1F48A")
    @meds[:vitamin_d]   = Med.new(name: :vitamin_d,   interval:24, required:24, default_dose:1000, max_dose:0,    dose_units: :iu,   emoji:"1F48A")
    @meds[:l_theanine]  = Med.new(name: :l_theanine,  interval:12, required:24, default_dose:1000, max_dose:0,    dose_units: :mg,   emoji:"1F48A")
  end

  # [
  #  0, #0 from me
  #  "chat574232935236064109", #1 chat id
  #  "2023-03-29 20:37:55", #2 readable time
  #  1680143875, #3 message time
  #  "1680194315", #4 current time
  #  "8:37:17 PM MDT\n" + #message
  #    "\n" +
  #    "Lyrica\n" +
  #    ".25mg Xanax\n" +
  #    "3/4 Baclofen\n" +
  #    "2 Liver\n" +
  #    "3 Bone Marrow\n" +
  #    "3000IU Vitamin D\n" +
  #    "10.5mg Iron\n" +
  #    "10.5mg Iron\n" +
  #    "500mg Taurine\n" +
  #    "500mg MSM\n" +
  #    "250mg Calcium",
  #  ],
  #
  def add_med(med:, epoch_time:, dose:nil, unit:nil)
    case med
    when /morph/i
      if dose == "7.5"
        @meds[:morphine_bt].log(epoch_time:epoch_time, dose:dose, units:unit)
      else
        @meds[:morphine].log(epoch_time:epoch_time, dose:dose, units:unit)
      end
    when /baclo/i
      if dose == "3/4"
        @meds[:baclofen].log(epoch_time:epoch_time, dose:7.5, units:"mg")
      else
        @meds[:baclofen].log(epoch_time:epoch_time, dose:dose, units:unit)
      end
    when /esgic/i
      @meds[:esgic].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /lyric/i
      @meds[:lyrica].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /xanax/i
      @meds[:xanax].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /taurine/i
      @meds[:taurine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /calcium/i
      @meds[:calcium].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /msm/i
      @meds[:msm].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /iron/i
      @meds[:iron].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /magnes/i
      @meds[:magnesium].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /nac/i
      @meds[:nac].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /vitamin\s*d/i
      @meds[:vitamin_d].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /theanine/i
      @meds[:l_theanine].log(epoch_time:epoch_time, dose:dose, units:unit)
    end
  end

  def blank_entry(size:0)
    entry = ""
    size.to_i.times do |i|
      entry += " "
    end

    entry
  end

  def dummy_array(entries)
    a = []
    (1..entries).each do |i|
      a << blank_entry
    end
    a
  end

  def pad_right(str, length)
    temp_str = Colors.strip_color(str)
    if temp_str.length < length
      # If the string is shorter than the desired length,
      # add spaces to the end until it is the desired length.
      str += " " * (length - temp_str.length)
    end
    str
  end

  def emoji?(str)
    str.codepoints.any? do |codepoint|
      @@emoji_ranges.any? { |range| range.include?(codepoint) }
    end
  end

  def line(color:242)
    "#{Colors.send("c#{color}")}-------------------------------------------------------------------------------------------------------------------------#{Colors.reset}"
  end

  def dash
    s = ""
    reset_meds
    db = IMessageChatDB.new
    @errors = ""
    @notes = ""

    db.get.each do |message|
      from_me, chat_id, message_time, message_epoch, current_epoch, message_body = message

      next if message_body.start_with?("Totals")
      next if message_body.start_with?("Edited to")

      message_body.split("\n").each do |line|
        case line
        when /[0-9]+\s*[aApP]/ # 10p 10a 9a
        when /[0-9]+:[0-9]+\s*[aApP]/ # 10:32p
        when /^\s*$/ # empty line
        when /^\s*[A-Za-z+]+\s*$/ # morphine
          add_med(med:line.strip, epoch_time:message_epoch)
        when /^\s*(-?\d*(\.\d+)?)\s+([A-Za-z()\s]+)$/ # 15 (morphine), .25 xanax, 7.5 morphine
          add_med(med:$3, epoch_time:message_epoch, dose: $1)
        when /^\s*(-?\d*(\.\d+)?)\s*([A-Za-z]+)\s+([A-Za-z0-9()\s\/-]+)”?\s*$/ # 15mg (morphine), .25mg xanax, 7.5 morphine, 2000iu vitamin d
          add_med(med:$4, epoch_time:message_epoch, dose: $1, unit:$3)
        when /^\s*([0-9\/]+)\s+([A-Za-z()\s]+)$/ # 3/4 baclofen
          add_med(med:$2, epoch_time:message_epoch, dose: $1)
        when /^\s*([\d\/]+)\/(\d+)$/ # ignore bp
          # ignore
        when /^[Nn]ote/
          @notes += "#{Time.at(message_epoch).strftime("%H:%M")} #{Colors.cyan}#{line.gsub(/Note:?\s*/,"")}#{Colors.reset}\n"
        when /^Laughed at/
        when /^Loved/
        when /^Liked/
        when @@emoji_regex
          # ignore
        else
          @errors += "parse_error: #{line}\n"
        end
      end
    end

    s += "#{dashboard_header}\n\n"

    meds.each_pair do |med, log|
      if med == :taurine
        s += "#{line(color:240)}\n"
      elsif  med == :magnesium || med == :esgic
        s += "\n"
      end

      s += "#{sprintf("%-12s", med)} #{log}\n"
    end

    s += "#{line(color: 250)}\n"
    s += "#{log_header}\n"

    log_records = []
    meds.each_pair do |med, log|
      log_summary_yesterday = log.list_yesterday_to_s
      log_list = log.list_to_s

      record = ""
      record += "#{log_summary_yesterday}" unless log_summary_yesterday.empty?
      record += "#{log_list}" unless log_list.empty?

      unless record.empty?
        record = "#{log.emoji} #{med}\n#{record}"
        log_records << record
      end

      log_records
    end

    max_col_width = Colors.strip_color(log_records.map{ |e| e.split("\n") }.flatten.max_by{|s| Colors.strip_color(s).length}).length

    log_columns = 6
    log_records.each_slice(log_columns) do |slice|
      a = slice.map{ |s| s.split("\n") }

      # zip truncates based on the shortest array
      # add empty array entries to equalize all arrays to be zipped
      max_rows = a.max_by(&:length).length
      a.each do |array|
        while array.length <= max_rows
          array << blank_entry(size: max_col_width)
        end
      end

      zipped_array = []
      a.each_with_index do  |arr, i|
        if i == 0
          zipped_array = arr.map{|a| [a]}
        else
          temp_array = zipped_array.zip(arr)
          zipped_array = temp_array.map(&:flatten)
        end
      end

      zipped_array.each do |row|
        array = row.map{|r| pad_right(r, max_col_width)}
        if row.any? {|str| emoji?(str) }
          s += "#{array.join(" ")}\n"
        else
          s += "#{array.join("  ")}\n"
        end
      end
    end

    s += "#{line(color:250)}\n"
    unless @notes.empty?
      s += "#{Colors.yellow}Notes#{Colors.reset}\n"
      s += "#{@notes}\n"
    end

    unless @errors.empty?
      s += "#{Colors.yellow}Errors#{Colors.reset}\n"
      s += "#{@errors}\n"
    end

    s
  end

  def dash_update_interval
    15
  end

  def dash_loop
    now = Time.now.to_i

    if (now - @last_dash_update) > dash_update_interval || @display_dash
      @display_dash = false
      print ANSI.clear
      ANSI.move_cursor(1,1)
      puts dash
      @last_dash_update = now
    end

    exit if @updater.updated?
  end

  def save_totals
    dir_path = "#{APP_PATH}/totals"
    yesterday_date = Date.today.prev_day.strftime('%Y-%m-%d')
    yesterday_file = "#{dir_path}/#{yesterday_date}"

    unless File.exist?(yesterday_file)

      puts "saving totals"

      save_data = {}
      save_data[:date] = yesterday_date
      save_data[:totals] = []

      meds.each_pair do |med, log|
        totals_data = {}
        totals_data[:med] = med
        totals_data[:total_dose] = log.total_dose_yesterday
        totals_data[:dose_units] = log.dose_units
        save_data[:totals] << totals_data
      end

      s = JSON.dump(save_data)

      begin
        File.write(yesterday_file, s)
        @save_totals = false
      rescue => exception
        puts "Error saving yesterday totals to #{yesterday_file}: #{exception.message}"
      end
    end

  end

  def totals
    dir_path = "#{APP_PATH}/totals"
    files = Dir.children(dir_path).sort.last(5)

    s = ""
    s += "#{dashboard_header}\n\n"

    files.each do |f|
      s += "#{File.read("#{dir_path}/#{f}")}\n"
    end

    s
  end

  def totals_loop
    now = Time.now.to_i

    if (now - @last_totals_update) > 3600 || @display_totals
      @display_totals = false
      print ANSI.clear
      ANSI.move_cursor(1,1)
      puts totals
      @last_totals_update = now
    end
  end

  def char_if_pressed
    c = nil

    begin
      # Set STDIN to raw mode
      STDIN.raw do |stdin|
        stdin.echo = false

        # Check if input is available
        if IO.select([STDIN], nil, nil, 0)
          # Read a single character from STDIN
          c = STDIN.getc
        end
      end

      # Convert the character code to a string if a character was read
      c.chr if c
    ensure
      # Reset STDIN to normal mode
      STDIN.echo = true
      STDIN.cooked!
    end
  end

  def run
    print ANSI.start_alternate_buffer
    print ANSI.hide_cursor

    begin
      loop do
        c = char_if_pressed
        case c
        when "d"
          @mode = "d"
          @display_dash = true
        when "t"
          @mode = "t"
          @display_totals = true
        when "s"
          @save_totals = true
        end

        case @mode
        when "d"
          dash_loop
        when "t"
          totals_loop
        end

        if Time.now.hour == 5 || @save_totals
          save_totals
        end
      end
    ensure
      print ANSI.clear
      print ANSI.end_alternative_buffer
      print ANSI.show_cursor
    end
  end

end


