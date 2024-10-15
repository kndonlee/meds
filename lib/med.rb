# frozen_string_literal: true

class Med
  SPEAKER_MUTED_EMOJI = "\u{1F507}"
  SPEAKER_EMOJI = "\u{1F508}"
  SLEEP_EMOJI = "\u{1F634}"

  class Dose

    attr_accessor :epoch_time, :dose, :dose_units

    def initialize(epoch_time:, dose:, dose_units:, half_life:)
      @epoch_time = epoch_time
      @dose_units = dose_units
      @dose = dose.to_f
      @half_life = half_life
    end

    def yesterday?
      @epoch_time > Med.last_5am_epoch_yesterday && @epoch_time < Med.last_5am_epoch
    end

    def to_s
      yesterday = yesterday? ? "#{Colors.c72} [Y]#{Colors.reset}" : ""
      t = Med.epoch_to_time_sc(epoch_time)
      "#{t} #{Colors.c183}#{dose} #{Colors.blue_bold}#{dose_units}#{Colors.reset}#{yesterday}"
    end

    def remaining_dose
      time_elapsed = Time.now.to_i - @epoch_time # seconds
      number_of_half_lives = time_elapsed / @half_life

      if number_of_half_lives <= 5
        remaining_dose = @dose * (0.5 ** number_of_half_lives)
      else
        remaining_dose = 0 # eliminated to 0 if greater than 5 half lives
      end

      remaining_dose
    end

  end

  attr_reader :emoji, :dose_units, :display, :display_log, :interval, :name, :announce

  @@meds = {}

  def initialize(name:, interval:, required:true, default_dose:, max_dose:0, dose_units:, display: :yes, display_log: true, emoji:, half_life:, announce:)
    @name = name
    @interval = interval
    @required = required
    @default_dose = default_dose
    @dose_units = dose_units
    @max_dose = max_dose
    @display = display
    @display_log = display_log
    @half_life = half_life
    @announce = announce

    @sleeping = true # whether kim is sleeping or awake, always start sleeping, then wake up via time passing or a call to being awake
    @dose_log = []
    @emoji = [emoji.hex].pack("U") # convert to unicode emoji
    @@meds[name] = self
    @skip = false

    @name_match = [@name.to_s]
  end

  def add_match_term(regex)
    @name_match << regex
  end

  def match?(string)
    @name_match.each do |regex|
      return true if string.strip =~ /#{regex}/i
    end

    false
  end

  def im_awake
    @sleeping = false
  end

  def skip_today
    @skip = true
  end

  def show_today
    @display = :yes
  end

  def hide_today
    @display = :no
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
    elsif @dose_units.to_s.downcase == "mg" && dose_units.to_s.downcase == "g"
      normalized_dose = normalized_dose * 1000
    elsif @dose_units.to_s.downcase == "g" && dose_units.to_s.downcase == "mg"
      normalized_dose = normalized_dose.to_f / 1000
    elsif @dose_units.to_s.downcase == "meq" && dose_units.to_s.downcase == "meqs"
      normalized_dose = normalized_dose.to_f
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
        half_life: @half_life
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

  def taken_today?
    if @dose_log.last.nil?
      return false
    else
      doses = @dose_log.select{|d| d.dose >= 0}
      if doses.empty?
        return false
      else
        if doses.last.epoch_time > Med.last_5am_epoch
          return true
        end
      end
    end

    false
  end

  # used for short hand display
  # return 1 of 3 options
  #   not_taken - red X
  #   in_progress - yello circle emoji
  #   finished - green check box emoji
  def finish_state
    if @dose_log.last.nil?
      return :not_taken
    else
      doses = @dose_log.select{|d| d.dose >= 0}
      if doses.empty?
        return :not_taken
      else
        if doses.last.epoch_time > Med.last_5am_epoch
          if total_dose >= @max_dose
            return :finished
          else
            return :in_progress
          end
        end
      end
    end

    :not_taken
  end

  def taken_yesterday?
    if @dose_log.last.nil?
      return false
    else
      doses = @dose_log.select{|d| d.dose >= 0}
      if doses.empty?
        return false
      else
        if doses.last.epoch_time > Med.last_5am_epoch_yesterday
          return true
        end
      end
    end

    false
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

  # calculated via elimination half lives
  def remaining_dose
    @dose_log.map(&:remaining_dose).sum
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
    #"#{Colors.c67_bg}#{Colors.c184}Optl#{Colors.reset}"
    "#{Colors.c208}Optl#{Colors.reset}"
  end

  def zzz_s
    "#{Colors.c218}zZzZ#{Colors.reset}"
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
    return true if @skip

    total_dose >= @max_dose && @max_dose != 0
  end

  def sleeping?
    return false if @display != :yes_awake  # only do sleep logic to entries that should be on awake

    current_time = Time.now
    # we are always awake after 3p
    awake_time = Time.new(current_time.year, current_time.month, current_time.day, 15, 0)
    # used for handling 12a to 5a period
    reset_day = Time.new(current_time.year, current_time.month, current_time.day, 5, 0)

    if (current_time <= reset_day) # before 5a, we are usually up
      false
    elsif (current_time <= awake_time) # true defers sleep determination logic to user
      @sleeping
    else
      false
    end
  end

  def due_to_s
    if done?
      done_s
    elsif sleeping?
      zzz_s
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

  def list_to_s(limit: 0)
    s = ""

    if (limit == 0)
      @dose_log.select {|d| d.epoch_time > Med.last_5am_epoch}.each do |d|
        s += "#{d.to_s}\n"
      end
    else
      @dose_log.select {|d| d.epoch_time > Med.last_5am_epoch}.last(limit).each do |d|
        s += "#{d.to_s}\n"
      end
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
    # every = "Every:#{Colors.cyan}#{interval}#{color_hrs}"
    # required = "Required:#{Colors.cyan}#{required_formatted}#{color_hrs}"
    interval = "Int:#{Colors.cyan}#{interval} #{Colors.reset}/#{Colors.cyan}#{required_formatted}#{color_hrs}"
    remaining = "Remaining:#{Colors.c218}#{sprintf("%7.2f",remaining_dose)} #{Colors.blue_bold}#{sprintf("%-04s",@dose_units)}#{Colors.reset}"
    total = "Total:#{Colors.purple_bold}#{dose}#{Colors.blue_bold} #{sprintf("%-04s",@dose_units)}#{Colors.reset}"
    total_yesterday = "Yesterday:#{Colors.purple_bold}#{dose_y}#{Colors.blue_bold} #{sprintf("%-04s",@dose_units)}#{Colors.reset}"

    announce = @announce ? "#{SPEAKER_EMOJI}" : "#{SPEAKER_MUTED_EMOJI}"
    sleep = (@display == :yes_awake) ? " #{SLEEP_EMOJI}" : ""

    "#{last}  #{elapsed}  #{due}  #{interval}  #{remaining} #{total} #{total_yesterday} #{announce}#{sleep}#{ANSI.clear_line_right}"
  end
end
