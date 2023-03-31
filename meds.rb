#!/usr/bin/env ruby

require 'sqlite3'
require 'io/console'

class Colors
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
    "\u001b[38;5;#{i}m"
  end

  def self.xterm_color_bg(i)
    "\u001b[48;5;#{i}m"
  end
  def self.xterm_bg(i)
    "\u001b[#{i}m"
  end

  def self.reset
    "\u001b[0m"
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
end

class Updater
  attr_reader :current_sha
  def initialize
    @current_sha = `git rev-parse HEAD`
  end

  def updated?
    `git pull`
    new_sha = `git rev-parse HEAD`

    new_sha != @current_sha
  end
end

class IMessageChatDB

  #@@query_history = 4 * 86400
  @@query_history = 86400
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

    def to_s
      t = Med.epoch_to_time_sc(epoch_time)
      "#{t} #{Colors.c183}#{dose} #{Colors.blue_bold}#{dose_units}#{Colors.reset}"
    end
  end

  def initialize(name:, interval:, required:true, default_dose:, dose_units:)
    @name = name
    @interval = interval
    @required = required
    @default_dose = default_dose
    @dose_units = dose_units

    @dose_log = []
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
      @dose_log.last.epoch_time
    end
  end

  def total_dose
    @dose_log.select { |dose| dose.epoch_time > last_5am_epoch}.map(&:dose).sum
  end

  def last_5am_epoch
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
    "#{Colors.green}wait#{Colors.reset}"
  end

  def due_to_s
    if elapsed > (@interval * 3600) && elapsed < (@required * 3600)
      optl_s
    elsif elapsed > (@required * 3600)
      take_s
    elsif elapsed < (@interval * 3600)
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
      "#{Colors.c208}#{time}#{Colors.c210}#{meridien}#{Colors.reset}"
    else
      "#{Colors.purple}#{time}#{Colors.c169}#{meridien}#{Colors.reset}"
    end
  end

  def last_dose_s
    if last_dose.nil?
      "#{Colors.cyan}NA     #{Colors.reset}"
    else
      Med.epoch_to_time_sc(last_dose)
    end
  end

  def list_to_s
    s = ""
    @dose_log.each do |d|
      s += "#{d.to_s}\n"
    end
    s
  end

  def color_hrs
    "#{Colors.blue_bold}hrs#{Colors.reset}"
  end

  def color_elapsed
    e = elapsed_to_s
    case e
    when /^01/
      "#{Colors.c70}#{elapsed_to_s}#{Colors.reset}"
    when /^0[23]/
      "#{Colors.c71}#{elapsed_to_s}#{Colors.reset}"
    when /^0[456]/
      "#{Colors.c72}#{elapsed_to_s}#{Colors.reset}"
    when /^0[789]/
      "#{Colors.c73}#{elapsed_to_s}#{Colors.reset}"
    when /^1/
      "#{Colors.c74}#{elapsed_to_s}#{Colors.reset}"
    else
      "#{Colors.c75}#{elapsed_to_s}#{Colors.reset}"
    end
  end

  def to_s
    interval = sprintf("%-2d", @interval)
    required = sprintf("%-2d", @required)

    "Last:#{last_dose_s}  Elapsed:#{color_elapsed}  Due:#{due_to_s}  Every:#{Colors.cyan}#{interval}#{color_hrs}  Required:#{Colors.cyan}#{required}#{color_hrs}  Total:#{Colors.purple_bold}#{total_dose}#{Colors.blue_bold} #{@dose_units}#{Colors.reset}"
  end
end

class MedDash

  attr_accessor :meds
  def initialize
    @version = "2.0.8"
    @hostname = `hostname`.strip
    reset_meds
  end

  def last_update_time
    Time.now.strftime("%a %Y-%m-%d %I:%M:%S%P")
  end

  def dashboard_header
    "#{Colors.yellow_bold}Last Update:#{Colors.purple_bold}#{last_update_time}  #{Colors.yellow_bold}Version:#{Colors.purple_bold}#{@version}  #{Colors.yellow_bold}Host:#{Colors.purple_bold}#{@hostname}#{Colors.reset}"
  end

  def log_header
    "#{Colors.yellow_bold}Log#{Colors.reset}"
  end

  def reset_meds
    # required == interval => TAKE
    # required >  interval => Optl to TAKE
    #
    @meds = {}
    @meds[:morphine]    = Med.new(name: :morphine,    interval:8,  required:8,  default_dose:15,   dose_units: :mg)
    @meds[:morphine_bt] = Med.new(name: :morphine_bt, interval:8,  required:24, default_dose:7.5,  dose_units: :mg)
    @meds[:baclofen]    = Med.new(name: :baclofen,    interval:4,  required:6,  default_dose:7.5,  dose_units: :mg)
    @meds[:esgic]       = Med.new(name: :esgic,       interval:4,  required:24, default_dose:1,    dose_units: :unit)
    @meds[:lyrica]      = Med.new(name: :lyrica,      interval:12, required:12, default_dose:150,  dose_units: :mg)
    @meds[:xanax]       = Med.new(name: :xanax,       interval:12, required:12, default_dose:0.25, dose_units: :mg)

    @meds[:taurine]     = Med.new(name: :taurine,     interval:3,  required:5,  default_dose:500,  dose_units: :mg)
    @meds[:calcium]     = Med.new(name: :calcium,     interval:3,  required:5,  default_dose:250,  dose_units: :mg)
    @meds[:msm]         = Med.new(name: :msm,         interval:3,  required:5,  default_dose:500,  dose_units: :mg)
    @meds[:iron]        = Med.new(name: :iron,        interval:3,  required:5,  default_dose:10.5, dose_units: :mg)
    @meds[:magnesium]   = Med.new(name: :magnesium,   interval:6,  required:6,  default_dose:48,   dose_units: :mg)
    @meds[:nac]         = Med.new(name: :nac,         interval:24, required:24, default_dose:600,  dose_units: :mg)
    @meds[:vitamin_d]   = Med.new(name: :vitamin_d,   interval:24, required:24, default_dose:1000, dose_units: :iu)
    @meds[:l_theanine]  = Med.new(name: :l_theanine,  interval:12, required:24, default_dose:1000, dose_units: :mg)
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
      if dose == 7.5
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
  temp_str = strip_color(str)
  if temp_str.length < length
    # If the string is shorter than the desired length,
    # add spaces to the end until it is the desired length.
    str += " " * (length - temp_str.length)
  end
  str
end

def strip_color(str)
  str.gsub(/[\x00-\x1F]\[[0-9;]+m/,'')
end

updater = Updater.new
md = MedDash.new

loop do
  system "clear"
  md.reset_meds
  db = IMessageChatDB.new
  $errors = ""

  db.get.each do |message|
    from_me, chat_id, message_time, message_epoch, current_epoch, message_body = message

    message_body.split("\n").each do |line|
      case line
      when /[0-9]+\s*[aApP]/ # 10p 10a 9a
      when /[0-9]+:[0-9]+\s*[aApP]/ # 10:32p
      when /^\s*$/ # empty line
      when /^\s*[A-Za-z+]+\s*$/ # morphine
        md.add_med(med:line.strip, epoch_time:message_epoch)
      when /^\s*(\d*(\.\d+)?)\s+([A-Za-z()\s]+)$/ # 15 (morphine), .25 xanax, 7.5 morphine
        md.add_med(med:$3, epoch_time:message_epoch, dose: $1)
      when /^\s*(\d*(\.\d+)?)\s*([A-Za-z]+)\s+([A-Za-z0-9()\s\/-]+)”?\s*$/ # 15mg (morphine), .25mg xanax, 7.5 morphine, 2000iu vitamin d
        md.add_med(med:$4, epoch_time:message_epoch, dose: $1, unit:$3)
      when /^\s*([0-9\/]+)\s+([A-Za-z()\s]+)$/ # 3/4 baclofen
        md.add_med(med:$2, epoch_time:message_epoch, dose: $1)
      else
        $errors += "unable to parse: #{line}\n"
      end
    end
  end

  puts md.dashboard_header
  puts
  md.meds.each_pair do |med, log|
    puts if med == :taurine || med == :magnesium
    puts "#{sprintf("%-12s", med)} #{log}"
  end

  puts
  puts md.log_header

  log_records = []
  md.meds.each_pair do |med, log|
    log_list = log.list_to_s
    unless log_list.empty?
      log_records << "#{med}\n#{log.list_to_s}"
    end
  end

  max_col_width = strip_color(log_records.map{ |e| e.split("\n") }.flatten.max_by{|s| strip_color(s).length}).length

  log_columns = 5
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
        zipped_array = arr
      else
        zipped_array = zipped_array.zip(arr).map(&:flatten)
      end
    end

    zipped_array.each do |row|
      array = row.map{|r| pad_right(r, max_col_width)}
      puts array.join("  ")
    end
  end

  puts
  puts "#{Colors.yellow}Errors#{Colors.reset}"
  puts $errors

  break if updater.updated?
  sleep(15)
end
