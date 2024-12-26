#!/usr/bin/env ruby

require 'date'
require 'sqlite3'
require 'io/wait'
require 'io/console'
require 'json'
require 'eventmachine'

require 'lib/i_message_chat_db'
require 'lib/ansi'
require 'lib/colors'
require 'lib/med'
require 'lib/med_logger'

APP_PATH = File.dirname(__FILE__)
$LOAD_PATH.unshift APP_PATH

$DEBUG = ENV["DEBUG"] == "true"
$HIDE_FORBIDDEN = ENV["HIDE_FORBIDDEN"] == "true"

MEDS = {}
MED_SETS = []

class Updater
  attr_reader :current_sha
  def initialize
    @current_sha = `git rev-parse HEAD`
    @update_interval = 300
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

$checkbox_emoji =  "\u{2705}"
$cross_emoji =  "\u{274C}"
$yellow_circle_emoji = "\u{1F7E1}"

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
  @@sun_emoji_regex = /^\u{1F31E}/

  attr_accessor :meds, :current_set_bump_epoch, :current_set_index
  def initialize
    @version = "5.0.0"
    @hostname = `hostname`.strip
    reset_meds

    @logger = MedLogger.instance
    @logger.log("MedDash started: version:#{@version} host:#{@hostname}")
    @logger.log("Ruby Version: #{RUBY_VERSION}")

    @updater = Updater.new
    @last_dash_update = Time.now.to_i
    @last_totals_update = Time.now.to_i
    @last_notes_update = Time.now.to_i
    @last_log_update = Time.now.to_i
    @mode = "d"
    @display_dash = true
    @display_totals = true
    @display_log = false
    @save_totals = false
    @muted = true
    @auto_show_narcotic = true

    @status_display_s = ""

    @current_set_index = 0
    @manual_set_increments = 0 # count of manual key presses
    @current_set_bump_epoch = Med.last_5am_epoch

    interval = 5
    @timer_thread = Thread.new do
      # initial sleep not to trigger mute sound
      sleep 5
      loop do
        med_count = med_count_to_take
        if med_count == 0
          interval = 5
        else
          announce_meds_due(false) unless @muted
          interval = 1800
        end

        sleep interval
      end
    end
  end

  def reset_bluetooth
    system("say 'restarting bluetooth daemon'")
    system("osascript -e 'do shell script \"killall bluetoothd\" with administrator privileges'")
  end

  def announce_meds_due(manual=true)
    med_count = med_count_to_take
    med_word = med_count == 1 ? "med" : "meds"
    system("say -v Daniel \"Kimberly, you now have #{med_count} #{med_word} due.\"")

    manual_word = manual ? "manually" : "automatically"
    @logger.log("announced #{med_count} #{manual_word}")
  end

  def med_count_to_take
    count = 0
    MEDS.each do |name, med|
      @logger.log("count state #{med.name} announce:#{med.announce} due:#{med.due?} done:#{med.done?}") if $DEBUG
      count += 1 if (med.announce && med.due? && !med.done?)
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
    med_count = "#{Colors.yellow_bold}Take Count:#{Colors.purple_bold}#{med_count_to_take}"

    usage = "#{Colors.yellow_bold}Usage: #{Colors.c47}[D]ash [L]og [T]otals #{notes_usage_string} [S]ave [A]nnounce [Q]uit #{mute_string}"
    elapsed_key = "#{Colors.yellow_bold}Elapsed: #{elapsed_color_guide}"

    rows, cols = STDOUT.winsize
    row_cols =  "#{Colors.yellow_bold}Window:#{Colors.purple_bold}#{rows}x#{cols}"
    actions_usage = "#{Colors.yellow_bold}Actions:#{Colors.purple_bold}Skip:#{Colors.yellow_bold}|#{Colors.purple_bold}Show:#{Colors.yellow_bold}|#{Colors.purple_bold}Hide:#{Colors.yellow_bold}|\u{1F31E}"
    auto_narcotic = "#{Colors.yellow_bold}AutoN: #{@auto_show_narcotic ? $checkbox_emoji : $cross_emoji}"

    if $HIDE_FORBIDDEN
      s = "#{Colors.c70_bg}#{last_update}  #{version}  #{host}  #{med_count}#{Colors.reset}#{ANSI.clear_line_right}\n"
    else
      s = "#{last_update}  #{version}  #{host} #{med_count} #{row_cols} #{actions_usage}#{ANSI.clear_line_right}\n"
    end
    s += "#{elapsed_key}    #{usage}  #{auto_narcotic}#{Colors.reset}#{ANSI.clear_line_right}"

    unless @status_display_s.empty?
      s += "\n#{Colors.c202_bg}Status: #{@status_display_s}#{Colors.reset}#{ANSI.clear_line_right}"
    end

    s
  end

  def log_header
    "#{ANSI.clear_line}\r#{Colors.yellow_bold}Log#{Colors.reset}#{ANSI.clear_line_right}"
  end

  def reset_meds
    MEDS.clear
    MED_SETS.clear
    load("medications.rb")
    MEDS.each do |key, med|
      med.set_dash(self)
    end
  end

  def hide_narcotics(epoch)
    hide("morphine_er", epoch)
    hide("morphine_ir", epoch)
    hide("dilauded", epoch)
    hide("oxycodone", epoch)
  end

  def toggle_narcotic_visibility(med, epoch)
    return unless @auto_show_narcotic

    case med
    when /morphine/i
      if med.match(/er/i)
        hide_narcotics(epoch)
        show("morphine_er", epoch)
      elsif med.match(/ir/i)
        hide_narcotics(epoch)
        show("morphine_ir", epoch)
      else
        hide_narcotics(epoch)
        show("morphine_er", epoch)
      end
    when /dilauded/i
      hide_narcotics(epoch)
      show("dilauded", epoch)
    when /oxycodone/i
      hide_narcotics(epoch)
      show("oxycodone", epoch)
    end
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
    @logger.log "add_med called with args: med=#{med} epoch_time=#{epoch_time} dose=#{dose} unit=#{unit}" if $DEBUG

    toggle_narcotic_visibility(med, epoch_time)

    # parse numbers
    dose = dose.to_r.to_f unless dose.nil?

    case med
    when /morph/i
      if med.match(/er/i)
        MEDS[:morphine_er].log(epoch_time:epoch_time, dose:dose, units:unit)
      elsif med.match(/ir/i)
        MEDS[:morphine_ir].log(epoch_time:epoch_time, dose:dose, units:unit)
      else
        MEDS[:morphine_er].log(epoch_time:epoch_time, dose:dose, units:unit)
      end

      # if dose == "7.5"
      #   # MEDS[:morphine_bt].log(epoch_time:epoch_time, dose:dose, units:unit)
      #   MEDS[:morphine_er].log(epoch_time:epoch_time, dose:dose, units:unit)
      # else
      #   MEDS[:morphine_er].log(epoch_time:epoch_time, dose:dose, units:unit)
      # end
    when /baclo/i
      if dose == "3/4"
        MEDS[:baclofen].log(epoch_time:epoch_time, dose:7.5, units:"mg")
      else
        MEDS[:baclofen].log(epoch_time:epoch_time, dose:dose, units:unit)
      end
    when /esgic/i
      MEDS[:esgic].log(epoch_time:epoch_time, dose:dose, units:unit)
      if (dose.nil?)
        @logger.log("tylenol dose default 325") if $DEBUG
        tylenol_dose = 325
      else
        tylenol_dose = dose * 325
      end

      # we don't want esgic to push tylenol forward, so submit current esgic as last tylenol dose time
      # should this be submitted as a 5am dose of the current day since we track the esgic anyway?
      last_dose_time = MEDS[:tylenol].last_dose
      if last_dose_time.nil?
        last_dose_time = epoch_time - (3600 * 4)
      end
      @logger.log "logging extra tylenol with dose #{tylenol_dose} for esgic dose #{dose}" if $DEBUG
      MEDS[:tylenol].log(epoch_time:last_dose_time, dose:tylenol_dose, units:"mg")
    when /^oxy/i
      MEDS[:oxycodone].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /lyric/i
      MEDS[:lyrica].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /xanax/i
      MEDS[:xanax].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /taurine/i
      MEDS[:taurine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /calcium/i
      MEDS[:calcium].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /msm/i
      MEDS[:msm].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /iron/i
      MEDS[:iron].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /magnes/i
      MEDS[:magnesium].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /nac/i
      MEDS[:nac].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /vitamin\s*d/i
      MEDS[:vitamin_d].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /theanine/i
      MEDS[:l_theanine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /apigenin/i
      MEDS[:apigenin].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /liver/i
      MEDS[:liver].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /marrow/i
      MEDS[:marrow].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /oyster/i
      MEDS[:oyster].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /phospholipid/i
      MEDS[:phospholipid_c].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /epa/i
      MEDS[:epa].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /dha/i
      MEDS[:dha].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /phenergan/i
      MEDS[:phenergan].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /famotidine/i
      MEDS[:famotidine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /hydroxyzine/i
      MEDS[:hydroxyzine].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /propranolol/i
      MEDS[:propranolol].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /propanolol/i
      MEDS[:propranolol].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /marshmallow/i
      MEDS[:marshmallow_r].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /soma/i
      MEDS[:soma].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /ondansetron/i
      MEDS[:ondansetron].log(epoch_time:epoch_time, dose:dose, units:unit)
    when /pc/i
      if dose == "1/4"
        MEDS[:phosphatidyl_c].log(epoch_time:epoch_time, dose:105, units:"mg")
      elsif dose == "1/2"
        MEDS[:phosphatidyl_c].log(epoch_time:epoch_time, dose:210, units:"mg")
      else
        MEDS[:phosphatidyl_c].log(epoch_time:epoch_time, dose:dose)
      end
    else
      return if med.match(/^L$/)

      MEDS.each do |med_name, med_entry|
        if med_entry.match?(med)
          med_entry.log(epoch_time:epoch_time, dose:dose, units:unit)
          next
        end
      end
    end
  end

  def bump_set(epoch_time:)
    @current_set_index += 1
    @current_set_bump_epoch = epoch_time
    @current_set_index = 0 if MED_SETS[@current_set_index].nil?
  end

  def update_status(str)
    @status_display_s = "#{str}"
  end

  def clear_status
    @status_display_s = ""
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
    # "#{Colors.send("c#{color}")}--------------------------------------------------------------------------------------------------------------------------------------------------------------#{Colors.reset}"
    "#{Colors.send("c#{color}")}------------------------------------------------------------------------------------------------------------------------------------------#{Colors.reset}#{ANSI.clear_line_right}"
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
        while array.length < max_rows
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

      print_empty_line = false
      zipped_array.each do |row|
        array = row.map{|r| pad_right(r, max_col_width)}
        if row.any? {|str| emoji?(str) }

          unless print_empty_line
            s += "#{ANSI.clear_line_right}\n"
          else
            print_empty_line = true
          end

          s += "#{array.join(" ").strip}#{ANSI.clear_line_right}\n"
        else
          s += "#{array.join("  ")}#{ANSI.clear_line_right}\n"
        end
      end
    end

    s.strip
  end

  def skip(med, epoch)
    MEDS.each do |med_name, med_entry|
      if med_entry.match?(med) && epoch > Med.last_5am_epoch
        med_entry.skip_today
        next
      end
    end
  end

  def show(med, epoch)
    MEDS.each do |med_name, med_entry|
      if med_entry.match?(med) && epoch > Med.last_5am_epoch
        med_entry.show_today
        next
      end
    end
  end

  def hide(med, epoch)
    MEDS.each do |med_name, med_entry|
      if med_entry.match?(med) && epoch > Med.last_5am_epoch
        med_entry.hide_today
        next
      end
    end
  end

  def im_awake
    MEDS.each do |med_name, med_entry|
      med_entry.im_awake
    end
  end

  def crack_meds
    reset_meds
    @errors = ""
    @notes = ""
    @current_set_index = 0
    db = IMessageChatDB.new

    db.get.each do |message|
      from_me, chat_id, message_time, message_epoch, current_epoch, message_body = message

      next if message_body.nil?
      next if message_body.start_with?("Totals")
      next if message_body.start_with?("Edited to")

      message_body.split("\n").each do |line|
        case line
        when /^[Nn]ote/
          puts "line case 9: #{line}" if $DEBUG
          @notes += "#{Time.at(message_epoch).strftime("%m/%d %H:%M")} #{Colors.cyan}#{line.gsub(/Note:?\s*/,"")}#{Colors.reset}\n"
        when /^[Ss]kip:\s*([A-Za-z()_\s]+)$/
          puts "line case 10: #{line}" if $DEBUG
          skip($1.strip, message_epoch)
        when /^[Hh]ide:\s*([A-Za-z()_\s]+)$/
          puts "line case 10: #{line}" if $DEBUG
          hide($1.strip, message_epoch)
        when /^[Ss]how:\s*([A-Za-z()_\s]+)$/
          puts "line case 10: #{line}" if $DEBUG
          show($1.strip, message_epoch)
        when @@sun_emoji_regex
          @logger.log("Parser matched awake signal, marking all meds as awake") if $DEBUG
          im_awake
        when /^[Ss]tatus:\s*clear$/i
          clear_status
        when /^[Ss]tatus:\s*(.*)$/
          update_status($1.strip)
        when /^[Aa]uto[Nn]:/
          @auto_show_narcotic ? @auto_show_narcotic = false : @auto_show_narcotic = true
        when /^1unit set/
          if (message_epoch > Med.last_5am_epoch)
            bump_set(epoch_time:message_epoch)
          end
        when /^[0-9]+:[0-9][0-9]:[0-9][0-9]\s*/ # 10:00:00
          @logger.log("Parser matched time in xx:xx:xx format: #{line}") if $DEBUG
        when /[0-9]+:[0-9][0-9]:[0-9][0-9]\s*[aApP]/ # 10:32:15p
          @logger.log("Parser matched time in xx:xx:xx AM format: #{line}") if $DEBUG
        when /[0-9]+\s*[aApP]\s*$/ # 10p 10a 9a
          @logger.log("Parser matched time in 10a format: #{line}") if $DEBUG
        when /[0-9]+:[0-9]+\s*[aApP]/ # 10:32p
          @logger.log("Parser matched time in 10:32a format: #{line}") if $DEBUG
        when /^\s*$/ # empty line
          @logger.log "line case 3: #{line}" if $DEBUG
        when /^\s*[A-Za-z+_]+\s*$/ # morphine
          @logger.log "line case 4: #{line}" if $DEBUG
          add_med(med:line.strip, epoch_time:message_epoch)
        when /^\s*(-?\d*(\.\d+)?)\s+([A-Za-z()_\s]+)$/ # 15 (morphine), .25 xanax, 7.5 morphine
          @logger.log "line case 5: #{line}" if $DEBUG
          add_med(med:$3, epoch_time:message_epoch, dose: $1)
        when /^\s*(-?\d*(\.\d+)?)\s*([A-Za-z]+)\s+([A-Za-z0-9()_\s\/-]+)”?\s*$/ # 15mg (morphine), .25mg xanax, 7.5 morphine, 2000iu vitamin d
          @logger.log "line case 6: #{line}" if $DEBUG
          add_med(med:$4, epoch_time:message_epoch, dose: $1, unit:$3)
        when /^\s*([0-9\/]+)\s+([A-Za-z()_\s]+)$/ # 3/4 baclofen
          @logger.log "line case 7: #{line}" if $DEBUG
          add_med(med:$2, epoch_time:message_epoch, dose: $1)
        when /^\s*([\d\/]+)\/(\d+)$/ # ignore bp
          @logger.log "line case 8: #{line}" if $DEBUG
          # ignore
        when /^Laughed at/
        when /^Loved/
        when /^Liked/
        when @@emoji_regex
          @logger.log "line case 10: #{line}" if $DEBUG
          # ignore
        else
          @errors += "parse_error: #{line}\n"
          @logger.log("parse_error: _#{line}_") if $DEBUG
        end
      end
    end
  end

  def log_dash(line_limit: 3, show_yesterday: false)
    s = ""

    log_records = []
    MEDS.each_pair do |med, log|
      next unless log.display_log
      next unless show?(med.to_s)

      log_summary_yesterday = log.list_yesterday_to_s
      log_list = log.list_to_s(limit: line_limit)

      record = ""
      if show_yesterday
        record += "#{log_summary_yesterday}" unless log_summary_yesterday.empty?
      end
      record += "#{log_list}" unless log_list.empty?

      unless record.empty?
        record = "#{log.emoji} #{med}\n#{record}"
        log_records << record
      end

      log_records
    end

    s += columnify(log_records:log_records, log_columns:7)

    s
  end

  def set_dash
    return "" if MED_SETS[@current_set_index].nil?

    total_increments = @manual_set_increments + @current_set_index
    index = total_increments % MED_SETS.length

    # Header
    # Next Set: Pre Set
    s = "#{ANSI.clear_line}\r#{Colors.yellow_bold}Set: #{Colors.reset}#{MED_SETS[index][:label]}#{ANSI.clear_line_right}\n#{ANSI.clear_line_right}\n"

    MED_SETS[index][:set].each do |set|
      med = set[:med]
      dose = set[:dose]
      s += "#{med.emoji} #{sprintf("%-18s", med.name)} Dose:#{Colors.c226}#{sprintf("%-15s", dose)}#{Colors.reset} #{med.to_set_s}\n"
    end
    s
  end

  def dash
    crack_meds
    s = "#{dashboard_header}#{ANSI.clear_line_right}\n#{ANSI.clear_line_right}\n"

    # Short Dash of Once-a-day entries
    MEDS.each_pair do |med, log|
      next if log.interval != 24
      next unless log.display == :yes || log.display == :yes_awake || log.display == :on_dose
      next unless show?(med.to_s)

      state = log.finish_state
      if state == :not_taken
        s += "#{$cross_emoji} #{med}   "
      elsif state == :in_progress
        s += "#{$yellow_circle_emoji} #{med} (#{log.total_dose})   "
      elsif state == :finished
        s += "#{$checkbox_emoji} #{med}   "
      else
        # we should never get here.
        s += "?? #{med}"
      end
    end

    s += "#{ANSI.clear_line_right}\n"
    s += "#{ANSI.clear_line}\n"

    MEDS.each_pair do |med, log|
      next if log.interval == 24
      next unless log.display == :yes || log.display == :yes_awake || log.display == :on_dose
      if log.display == :on_dose
        next unless log.taken_yesterday?
      end
      next unless show?(med.to_s)

      if med == :taurine
        s += "#{line(color:240)}\n"
      elsif  med == :msm || med == :esgic || med == :azelastine
        s += "#{ANSI.clear_line}\n"
      end

      s += "#{log.emoji} #{sprintf("%-14s", med)} #{log}\n"
    end

    s += "#{line(color: 250)}\n"

    s += "#{set_dash}#{ANSI.clear_line_right}\n"

    # s += "#{log_header}\n"
    # s += log_dash

    s
  end

  def log
    crack_meds
    s = "#{dashboard_header}\n\n"
    s += log_dash(line_limit: 100, show_yesterday: true)
    s
  end

  def log_loop
    now = Time.now.to_i
    print ANSI.clear if @display_log

    if (now - @last_log_update) > 3600 || @display_log
      @display_log = false
      print ANSI.clear
      ANSI.move_cursor(1,1)
      puts log
      @last_log_update = now
    end
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
    0
  end

  # after printing everything, there can be leftover text from the prior loop
  # clean them up
  def cleanup_empty_lines
    row, col = ANSI.cursor_position
    win_row, win_col = STDOUT.winsize
    lines_to_clear = win_row - row
    lines_to_clear.times do
      puts ANSI.clear_line
    end
  end

  def dash_loop
    now = Time.now.to_i

    if (now - @last_dash_update) > dash_update_interval || @display_dash
      @display_dash = false
      #print ANSI.clear
      ANSI.move_cursor(1,1)
      puts dash
      @last_dash_update = now

      cleanup_empty_lines
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

      MEDS.each_pair do |med, log|
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

  def show?(med)
    return true unless $HIDE_FORBIDDEN

    case med
    when "morphine"
      false
    when "docusate"
      false
    when "soma"
      false
    when "xanax"
      false
    else
      true
    end
  end

  def totals
    dir_path = "#{APP_PATH}/totals"
    files = Dir.children(dir_path).sort.last(30)

    s = ""
    s += "#{dashboard_header}\n\n"

    max_row_count = 0
    row_count = 0

    records = []
    files.each do |f|
      next unless f.match(/^\d\d\d\d-\d\d-\d\d$/)

      data = JSON.parse(File.read("#{dir_path}/#{f}"))
      s2 = "#{Colors.c208}#{data["date"]}#{Colors.reset}\n"
      data["totals"].each do |med|
        if med["total_dose"] > 0 && show?(med["med"])
          s2 += "#{med["med"]} #{Colors.c183}#{med["total_dose"]} #{Colors.blue_bold}#{med["dose_units"]}#{Colors.reset}\n"
          row_count += 1
        end
      end
      s2 += "\n"

      max_row_count = row_count if row_count > max_row_count
      row_count = 0

      records << s2
    end

    # calculate space available to display log
    rows, cols = STDOUT.winsize
    max_col_width = Colors.strip_color(records.map{ |e| e.split("\n") }.flatten.max_by{|s| Colors.strip_color(s).length}).length
    rows_to_display = ((rows - 3) / max_row_count).to_i
    cols_to_display = (cols / (max_col_width + 2)).to_i
    entries_to_display = rows_to_display * cols_to_display
    slice_start = records.length - entries_to_display
    slice_end = records.length

    # puts "rows:#{rows} display_rows:#{rows_to_display} max_row_count:#{max_row_count} display_cols:#{cols_to_display}"

    records_to_display = records.slice(slice_start, slice_end)

    s += columnify(log_records:records_to_display.reverse, log_columns:cols_to_display)

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
            @mode = "l"
            @display_log = true
          elsif @mode == "l"
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
        when "l"
          @mode = "l"
          @display_log = true
        when "t"
          @mode = "t"
          @display_totals = true
        when "a"
          announce_meds_due(true)
        when "s"
          @save_totals = true
        when "n"
          @mode = "n"
          @display_notes = true
        when "b"
          reset_bluetooth
        when "m"
          if @muted
            @muted = false
            @display_dash = true
          else
            @muted = true
            @display_dash = true
          end
        when "k"
          @manual_set_increments += 1
        when "q"
          exit
        end

        case @mode
        when "d"
          dash_loop
        when "l"
          log_loop
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

  # runs on application exit
  def cleanup
    @logger.log('MedDash quitting.')
    @logger.close
  end
end


