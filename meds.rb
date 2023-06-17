#!/usr/bin/env ruby

require 'date'
require 'sqlite3'
require 'io/wait'
require 'io/console'
require 'json'
require 'eventmachine'

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

  attr_reader :emoji, :dose_units, :display, :display_log

  @@meds = {}

  def initialize(name:, interval:, required:true, default_dose:, max_dose:0, dose_units:, display:true, display_log: true, emoji:)
    @name = name
    @interval = interval
    @required = required
    @default_dose = default_dose
    @dose_units = dose_units
    @max_dose = max_dose
    @display = display
    @display_log = display_log

    @dose_log = []
    @emoji = [emoji.hex].pack("U") # convert to unicode emoji
    @@meds[name] = self
    @skip = false
  end

  def match?(string)
    @name.downcase.match?(string.strip.downcase)
  end

  def skip_today
    @skip = true
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
      86400 * 2
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
      doses = @dose_log.select{|d| d.dose >= 0}
      if doses.empty?
        nil
      else
        doses.last.epoch_time
      end
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
    if @name == :morphine
      if @@meds[:morphine_bt].wait?
        false
      else
        elapsed > (@required * 3600)
      end
    else
      elapsed > (@required * 3600)
    end
  end

  def wait?
    elapsed < (@interval * 3600)
  end

  def done?
    total_dose >= @max_dose && @max_dose != 0
  end

  def due_to_s
    if done? || @skip
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
    yesterday_doses = @dose_log.select { |dose| dose.epoch_time > Med.last_5am_epoch_yesterday && dose.epoch_time < Med.last_5am_epoch && dose.dose > 0}

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
    @dose_log.select {|d| d.epoch_time > Med.last_5am_epoch && d.dose > 0}.each do |d|
      s += "#{d.to_s}\n"
    end
    s
  end

  def color_hrs
    "#{Colors.blue_bold}h#{Colors.reset}"
  end

  def color_elapsed
    colors = [70,71,72,73,74,75,69,63,57,56,55,54,53]
    required_s = @required * 3600
    elapsed_s = elapsed

    if elapsed_s > required_s
      color_index = colors.length - 1
    else
      color_index = (((elapsed / required_s.to_f) * colors.length).round)
    end

    if color_index >= colors.length
      color_index = colors.length - 1
    end

    "#{Colors.send("c#{colors[color_index]}")}#{elapsed_to_s}#{Colors.reset}"

    # e = elapsed_to_s
    # if e =~ /^00:/
    #   "#{Colors.c70}#{elapsed_to_s}#{Colors.reset}"
    # elsif e =~ /^0[1]:/
    #   "#{Colors.c71}#{elapsed_to_s}#{Colors.reset}"
    # elsif e =~ /^0[345]:/
    #   "#{Colors.c72}#{elapsed_to_s}#{Colors.reset}"
    # elsif e =~ /^0[6789]:/
    #   "#{Colors.c73}#{elapsed_to_s}#{Colors.reset}"
    # elsif e =~ /^1.:/
    #   "#{Colors.c74}#{elapsed_to_s}#{Colors.reset}"
    # else #20 hrs and beyond
    #   "#{Colors.c75}#{elapsed_to_s}#{Colors.reset}"
    # end
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
  SPEAKER_MUTED_EMOJI = "\u{1F507}"
  SPEAKER_EMOJI = "\u{1F508}"

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
    @version = "2.4.5"
    @hostname = `hostname`.strip
    reset_meds

    @updater = Updater.new
    @last_dash_update = Time.now.to_i
    @last_totals_update = Time.now.to_i
    @last_notes_update = Time.now.to_i
    @mode = "d"
    @display_dash = true
    @display_totals = true
    @save_totals = false
    @muted = true

    interval = 5
    @timer_thread = Thread.new do
      loop do
        med_count = med_count_to_take
        if med_count == 0
          interval = 5
        else
          announce_meds_due unless @muted
          interval = 1800
        end

        sleep interval
      end
    end
  end

  def announce_meds_due
    med_count = med_count_to_take
    med_word = med_count == 1 ? "med" : "meds"
    system("say -v Daniel \"Kimberly, you now have #{med_count} #{med_word} due.\"")
  end

  def med_count_to_take
    count = 0
    @meds.each do |name, med|
      count += 1 if (med.due? && !med.done? && med.display)
    end
    count
  end

  def last_update_time
    Time.now.strftime("%a %Y-%m-%d %I:%M:%S%P")
  end

  def elapsed_color_guide
    s = ""
    [70,71,72,73,74,75,69,63,57,56,55,54,53].each do |i|
      code = i.to_s
      s += "\u001b[48;5;#{code}m  "
    end
    s += "\u001b[0m"
    s
  end
  def dashboard_header
    mute_string = @muted ? "un[M]ute #{SPEAKER_MUTED_EMOJI}" : "[M]ute #{SPEAKER_EMOJI}"

    notes_usage_string = @notes.empty? ? "[N]otes" : "[N]otes#{Colors.white_bold}*#{Colors.c47}"

    last_update = "#{Colors.yellow_bold}Last Update:#{Colors.purple_bold}#{last_update_time}"
    version = "#{Colors.yellow_bold}Version:#{Colors.purple_bold}#{@version}"
    host = "#{Colors.yellow_bold}Host:#{Colors.purple_bold}#{@hostname}"
    usage = "#{Colors.yellow_bold}Usage: #{Colors.c47}[D]ash [T]otals #{notes_usage_string} [S]ave [A]nnounce [Q]uit #{mute_string}"
    elapsed_key = "#{Colors.yellow_bold}Elapsed: #{elapsed_color_guide}"

    s = "#{last_update}  #{version}  #{host}\n"
    s += "#{elapsed_key}    #{usage}#{Colors.reset}"
    s
  end

  def log_header
    "#{Colors.yellow_bold}Log#{Colors.reset}"
  end

  def reset_meds
    # required == interval => TAKE
    # required >  interval => Optl to TAKE
    #
    @meds = {}
    @meds[:morphine]       = Med.new(name: :morphine,       interval:8,  required:12, default_dose:15,   max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F480")
    @meds[:morphine_bt]    = Med.new(name: :morphine_bt,    interval:8,  required:48, default_dose:7.5,  max_dose:0,     dose_units: :mg,   display:true,  display_log:false, emoji:"1F48A")
    @meds[:baclofen]       = Med.new(name: :baclofen,       interval:4,  required:8,  default_dose:7.5,  max_dose:0,     dose_units: :mg,   display:true,  display_log:true,  emoji:"26A1")
    @meds[:lyrica]         = Med.new(name: :lyrica,         interval:12, required:12, default_dose:150,  max_dose:0,     dose_units: :mg,   display:true,  display_log:true,  emoji:"1F9E0")

    @meds[:esgic]          = Med.new(name: :esgic,          interval:4,  required:48, default_dose:1,    max_dose:0,     dose_units: :unit, display:true,  display_log:true,  emoji:"1F915")
    @meds[:tylenol]        = Med.new(name: :tylenol,        interval:4,  required:48, default_dose:500,  max_dose:0,     dose_units: :mg,   display:true,  display_log:true,  emoji:"1F915")
    @meds[:xanax]          = Med.new(name: :xanax,          interval:4,  required:8,  default_dose:0.25, max_dose:0,     dose_units: :mg,   display:true,  display_log:true,  emoji:"1F630")
    @meds[:phenergan]      = Med.new(name: :phenergan,      interval:4,  required:48, default_dose:25,   max_dose:0,     dose_units: :mg,   display:true,  display_log:false, emoji:"1F48A")
    @meds[:ondansetron]    = Med.new(name: :ondansetron,    interval:4,  required:48, default_dose:4,    max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")

    @meds[:taurine]        = Med.new(name: :taurine,        interval:3,  required:4,  default_dose:500,  max_dose:6500,  dose_units: :mg,   display:true,  display_log:true,  emoji:"1F48A")
    @meds[:calcium]        = Med.new(name: :calcium,        interval:3,  required:4,  default_dose:250,  max_dose:1750,  dose_units: :mg,   display:true,  display_log:true,  emoji:"1F9B4")
    @meds[:iron]           = Med.new(name: :iron,           interval:48, required:48, default_dose:10.5, max_dose:52.5,  dose_units: :mg,   display:true,  display_log:true,  emoji:"1FA78")
    @meds[:vitamin_d]      = Med.new(name: :vitamin_d,      interval:3,  required:4,  default_dose:1000, max_dose:3000,  dose_units: :iu,   display:true,  display_log:true,  emoji:"1F48A")

    @meds[:msm]            = Med.new(name: :msm,            interval:1.75, required:2,default_dose:500,  max_dose:2000,  dose_units: :mg,   display:true,  display_log:true,  emoji:"26FD")
    @meds[:magnesium]      = Med.new(name: :magnesium,      interval:3,  required:3,  default_dose:48,   max_dose:192,   dose_units: :mg,   display:true,  display_log:true,  emoji:"1F48A")
    @meds[:nac]            = Med.new(name: :nac,            interval:24, required:24, default_dose:600,  max_dose:600,   dose_units: :mg,   display:true,  display_log:true,  emoji:"1F48A")
    @meds[:l_theanine]     = Med.new(name: :l_theanine,     interval:1,  required:48, default_dose:50,   max_dose:900,   dose_units: :mg,   display:true,  display_log:true,  emoji:"1F48A")
    @meds[:apigenin]       = Med.new(name: :apigenin,       interval:12, required:48, default_dose:25,   max_dose:0,     dose_units: :mg,   display:true,  display_log:true,  emoji:"1F48A")

    @meds[:liver]          = Med.new(name: :liver,          interval:12, required:48, default_dose:1,    max_dose:0,     dose_units: :unit, display:false, display_log:false, emoji:"1F48A")
    @meds[:marrow]         = Med.new(name: :marrow,         interval:12, required:48, default_dose:1,    max_dose:0,     dose_units: :unit, display:false, display_log:false, emoji:"1F48A")
    @meds[:oyster]         = Med.new(name: :oyster,         interval:12, required:48, default_dose:1,    max_dose:0,     dose_units: :unit, display:false, display_log:false, emoji:"1F48A")
    @meds[:phospholipid_c] = Med.new(name: :phospholipid_c, interval:12, required:48, default_dose:1300, max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:epa]            = Med.new(name: :epa,            interval:12, required:48, default_dose:1000, max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:dha]            = Med.new(name: :dha,            interval:12, required:48, default_dose:1000, max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:famotidine]     = Med.new(name: :famotidine,     interval:4,  required:48, default_dose:20,   max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:hydroxyzine]    = Med.new(name: :hydroxyzine,    interval:4,  required:48, default_dose:25,   max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:propranolol]    = Med.new(name: :propranolol,    interval:12, required:48, default_dose:80,   max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:soma]           = Med.new(name: :soma,           interval:4,  required:48, default_dose:350,  max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    @meds[:marshmallow_r]  = Med.new(name: :marshmallow_r,  interval:24, required:48, default_dose:200,  max_dose:0,     dose_units: :mg,   display:false, display_log:false, emoji:"1F48A")
    # 137ug per spray, 2x per nostril = 548ug
    @meds[:azelastine]     = Med.new(name: :azelastine,     interval:24, required:48, default_dose:548,  max_dose:0,     dose_units: :ug,   display:true,  display_log:false, emoji:"1F48A")
    # 27.5ug per spray, 2x per nostril = 100ug
    @meds[:veramyst]       = Med.new(name: :veramyst,       interval:24, required:48, default_dose:110,  max_dose:0,     dose_units: :ug,   display:true,  display_log:false, emoji:"1F48A")
    @meds[:metoclopramide] = Med.new(name: :metoclopramide, interval:24, required:48, default_dose:10,   max_dose:0,     dose_units: :mg,   display:false,  display_log:false, emoji:"1F48A")
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
      if (dose.nil?)
        tylenol_dose = 325
      else
        tylenol_dose = dose * 325
      end

      # we don't want esgic to push tylenol forward, so submit current esgic as last tylenol dose time
      # should this be submitted as a 5am dose of the current day since we track the esgic anyway?
      last_dose_time = @meds[:tylenol].last_dose
      if last_dose_time.nil?
        last_dose_time = epoch_time - (3600 * 4)
      end
      @meds[:tylenol].log(epoch_time:last_dose_time, dose:tylenol_dose, units:"mg")
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
    when /apigenin/i
      @meds[:apigenin].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /liver/i
      @meds[:liver].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /marrow/i
      @meds[:marrow].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /oyster/i
      @meds[:oyster].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /phospholipid/i
      @meds[:phospholipid_c].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /epa/i
      @meds[:epa].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /dha/i
      @meds[:dha].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /phenergan/i
      @meds[:phenergan].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /famotidine/i
      @meds[:famotidine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /hydroxyzine/i
      @meds[:hydroxyzine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /propranolol/i
    when /propanolol/i
      @meds[:propranolol].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /marshmallow/i
      @meds[:marshmallow_r].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /soma/i
      @meds[:soma].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /ondansetron/i
      @meds[:ondansetron].log(epoch_time:epoch_time, dose:dose, units:unit)
    else
      @meds.each do |med_name, med_entry|
        if med_entry.match?(med)
          med_entry.log(epoch_time:epoch_time, dose:dose, units:unit)
          next
        end
      end
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
    "#{Colors.send("c#{color}")}-----------------------------------------------------------------------------------------------------------------------------------------#{Colors.reset}"
  end

  def columnify(log_records:, log_columns:7)
    s = ""

    max_col_width = Colors.strip_color(log_records.map{ |e| e.split("\n") }.flatten.max_by{|s| Colors.strip_color(s).length}).length

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
    s
  end

  def skip(med, epoch)
    @meds.each do |med_name, med_entry|
      if med_entry.match?(med) && epoch > Med.last_5am_epoch
        med_entry.skip_today
        next
      end
    end
  end

  def dash
    s = ""
    reset_meds
    db = IMessageChatDB.new
    @errors = ""
    @notes = ""

    db.get.each do |message|
      from_me, chat_id, message_time, message_epoch, current_epoch, message_body = message

      next if message_body.nil?
      next if message_body.start_with?("Totals")
      next if message_body.start_with?("Edited to")

      message_body.split("\n").each do |line|
        case line
        when /^[Nn]ote/
          puts "line case 9: #{line}" if ENV["DEBUG"] == "true"
          @notes += "#{Time.at(message_epoch).strftime("%m/%d %H:%M")} #{Colors.cyan}#{line.gsub(/Note:?\s*/,"")}#{Colors.reset}\n"
        when /^[Ss]kip:\s*([A-Za-z()\s]+)$/
          puts "line case 10: #{line}" if ENV["DEBUG"] == "true"
          skip($1.strip, message_epoch)
        when /[0-9]+\s*[aApP]/ # 10p 10a 9a
          puts "line case 1: #{line}" if ENV["DEBUG"] == "true"
        when /[0-9]+:[0-9]+\s*[aApP]/ # 10:32p
          puts "line case 2: #{line}" if ENV["DEBUG"] == "true"
        when /^\s*$/ # empty line
          puts "line case 3: #{line}" if ENV["DEBUG"] == "true"
        when /^\s*[A-Za-z+]+\s*$/ # morphine
          puts "line case 4: #{line}" if ENV["DEBUG"] == "true"
          add_med(med:line.strip, epoch_time:message_epoch)
        when /^\s*(-?\d*(\.\d+)?)\s+([A-Za-z()\s]+)$/ # 15 (morphine), .25 xanax, 7.5 morphine
          puts "line case 5: #{line}" if ENV["DEBUG"] == "true"
          add_med(med:$3, epoch_time:message_epoch, dose: $1)
        when /^\s*(-?\d*(\.\d+)?)\s*([A-Za-z]+)\s+([A-Za-z0-9()\s\/-]+)”?\s*$/ # 15mg (morphine), .25mg xanax, 7.5 morphine, 2000iu vitamin d
          puts "line case 6: #{line}" if ENV["DEBUG"] == "true"
          add_med(med:$4, epoch_time:message_epoch, dose: $1, unit:$3)
        when /^\s*([0-9\/]+)\s+([A-Za-z()\s]+)$/ # 3/4 baclofen
          puts "line case 7: #{line}" if ENV["DEBUG"] == "true"
          add_med(med:$2, epoch_time:message_epoch, dose: $1)
        when /^\s*([\d\/]+)\/(\d+)$/ # ignore bp
          puts "line case 8: #{line}" if ENV["DEBUG"] == "true"
          # ignore
        when /^Laughed at/
        when /^Loved/
        when /^Liked/
        when @@emoji_regex
          puts "line case 10: #{line}" if ENV["DEBUG"] == "true"
          # ignore
        else
          @errors += "parse_error: #{line}\n"
        end
      end
    end

    s += "#{dashboard_header}\n\n"

    meds.each_pair do |med, log|
      next unless log.display

      if med == :taurine
        s += "#{line(color:240)}\n"
      elsif  med == :msm || med == :esgic || med == :azelastine
        s += "\n"
      end

      s += "#{sprintf("%-12s", med)} #{log}\n"
    end

    s += "#{line(color: 250)}\n"
    s += "#{log_header}\n"

    log_records = []
    meds.each_pair do |med, log|
      next unless log.display_log

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

    log_columns = 7
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

    s
  end

  def notes
    s = ""
    s += "#{dashboard_header}\n\n"

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

  def notes_loop
    now = Time.now.to_i

    print ANSI.clear if @display_notes

    if (now - @last_notes_update) > 3600 || @display_notes
      @display_notes = false
      print ANSI.clear
      ANSI.move_cursor(1,1)
      puts notes
      @last_notes_update = now
    end
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
    files = Dir.children(dir_path).sort.last(14)

    s = ""
    s += "#{dashboard_header}\n\n"

    records = []
    files.each do |f|
      data = JSON.parse(File.read("#{dir_path}/#{f}"))
      s2 = "#{Colors.c208}#{data["date"]}#{Colors.reset}\n"
      data["totals"].each do |med|
        if med["total_dose"] > 0
          s2 += "#{med["med"]} #{Colors.c183}#{med["total_dose"]} #{Colors.blue_bold}#{med["dose_units"]}#{Colors.reset}\n"
        end
      end
      s2 += "\n"

      records << s2
    end

    s += columnify(log_records:records.reverse, log_columns:7)

    s
  end

  def totals_loop
    now = Time.now.to_i

    print ANSI.clear if @display_totals

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
        when " "
          if @mode == "n"
            @mode = "d"
            @display_dash = true
          elsif @mode == "d"
            @mode = "t"
            @display_totals = true
          elsif @mode == "t"
            @mode = "n"
            @display_notes = true
          else
            @mode = "d"
            @display_dash = true
          end
        when "d"
          @mode = "d"
          @display_dash = true
        when "t"
          @mode = "t"
          @display_totals = true
        when "a"
          announce_meds_due
        when "s"
          @save_totals = true
        when "n"
          @mode = "n"
          @display_notes = true
        when "m"
          if @muted
            @muted = false
            @display_dash = true
          else
            @muted = true
            @display_dash = true
          end
        when "q"
          exit
        end

        case @mode
        when "d"
          dash_loop
        when "t"
          totals_loop
        when "n"
          notes_loop
        end

        sleep(0.1)

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


