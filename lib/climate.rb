# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Climate page for MedDash: CO2 / temperature / AC state from the airctl daemon (meds/airctl),
# a 24h timeline, and an event log explaining why the AC turned on/off, plus comfort feedback keys.
#
# Data comes from the airctl daemon running on this same Mac (meds/airctl, :8788), so the whole
# package runs wherever it is installed. To view another machine's daemon instead, set e.g.
#   CLIMATE_URL=http://Kimberlys-iMac-M3.local:8788
class Climate
  DEFAULT_URL = 'http://127.0.0.1:8788'
  REFRESH_SECONDS = 20
  HOURS = 24
  BUCKET_MINUTES = 30

  FEEDBACK_KEYS = {
    '1' => ['too_warm', 'too warm'],
    '2' => ['too_cold', 'too cold'],
    '3' => ['stuffy', 'stuffy'],
    '4' => ['too_loud', 'too loud'],
    '0' => ['ok', 'feels ok'],
  }.freeze

  attr_reader :updated_at

  def initialize(url: ENV['CLIMATE_URL'] || DEFAULT_URL)
    @url = url.chomp('/')
    @lock = Mutex.new
    @data = nil
    @error = nil
    @updated_at = 0
    @message = nil
    @thread = Thread.new { loop { refresh; sleep REFRESH_SECONDS } }
  end

  def refresh
    data = get("/history?hours=#{HOURS}")
    @lock.synchronize { @data = data; @error = nil; @updated_at = Time.now.to_i }
  rescue StandardError => e
    @lock.synchronize { @error = e.message; @updated_at = Time.now.to_i }
  end

  # Returns true if the key was a feedback key.
  def handle_key(c)
    fb = FEEDBACK_KEYS[c]
    return false unless fb

    Thread.new do
      get("/feedback?value=#{fb[0]}")
      @message = "Logged \"#{fb[1]}\" at #{Time.now.strftime('%H:%M')} -- thanks!"
      refresh
    rescue StandardError => e
      @message = "Could not log feedback: #{e.message}"
    end
    true
  end

  def render(header, cols: 120, rows: 40)
    data, error = @lock.synchronize { [@data, @error] }
    out = +"#{header}\n\n"
    if data.nil?
      out << "#{Colors.yellow_bold}Climate#{Colors.reset}  connecting to #{@url} ...\n"
      if error&.include?('refused') && @url.include?('127.0.0.1')
        out << "\n#{Colors.c244}airctl isn't running on this Mac. Start it with:\n" \
               "  cd #{File.expand_path('../airctl', __dir__)} && ./setup.sh && ./airctlctl install-service\n" \
               "or view another Mac's: CLIMATE_URL=http://<host>.local:8788 ./meds#{Colors.reset}\n"
      elsif error
        out << "#{Colors.c196}#{error}#{Colors.reset}\n"
      end
      return out
    end

    st = data['status'] || {}
    colors = st['colors'] || [1100, 1500]
    out << current_line(st, colors, error) << "\n"
    (st['features'] || {}).each { |name, f| out << feature_line(name, f) << "\n" }
    out << "\n" << timeline(data, colors, cols) << "\n"
    out << "#{Colors.yellow_bold}Feedback:#{Colors.c47} " +
           FEEDBACK_KEYS.map { |k, (_, label)| "[#{k}] #{label}" }.join('  ') + "#{Colors.reset}"
    out << "   #{Colors.c214}#{@message}#{Colors.reset}" if @message
    out << "\n\n"
    used = out.count("\n")
    out << event_log(data['events'] || [], colors, [rows - used - 2, 3].max)
    out
  end

  private

  def get(path)
    uri = URI("#{@url}#{path}")
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 5) { |h| h.get(uri.request_uri) }
    raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  def co2_color(v, colors)
    return Colors.c244 if v.nil?
    return Colors.c196 if v >= colors[1]
    return Colors.c208 if v >= colors[0]

    Colors.c40
  end

  def co2_bg(v, colors)
    return Colors.c236_bg if v.nil?
    return Colors.c160_bg if v >= colors[1]
    return Colors.c172_bg if v >= colors[0]

    Colors.c28_bg
  end

  def ago(ts)
    return '?' if ts.nil?

    s = (Time.now.to_f - ts).to_i
    return "#{s}s" if s < 120
    return "#{s / 60}m" if s < 7200

    "#{s / 3600}h#{(s % 3600) / 60}m"
  end

  def current_line(st, colors, error)
    co2 = st['co2']
    stale = st['reading_ts'] && Time.now.to_f - st['reading_ts'] > 300
    s = +"#{Colors.yellow_bold}Climate  #{co2_color(co2, colors)}CO2 #{co2 || '--'} ppm#{Colors.reset}"
    s << "   #{Colors.white_bold}#{st['temp_f'] ? format('%.1f', st['temp_f']) : '--'}F#{Colors.reset}"
    s << "   #{Colors.c39}#{st['humidity'] || '--'}% RH#{Colors.reset}"
    s << "   #{Colors.c244}reading #{ago(st['reading_ts'])} ago#{Colors.reset}"
    s << "   #{Colors.c196}SENSOR STALE#{Colors.reset}" if stale
    s << "   #{Colors.c196}(dashboard: #{error})#{Colors.reset}" if error
    s
  end

  def feature_line(name, f)
    state = f['on'] ? "#{Colors.c39}ON #{Colors.reset}" : "#{Colors.c244}off#{Colors.reset}"
    s = +"  #{Colors.white_bold}#{name.ljust(12)}#{Colors.reset}#{state}"
    s << " for #{ago(f['since'])}" if f['since']
    s << "  #{Colors.c214}(min #{f['on'] ? 'run' : 'rest'} #{f['hold_remaining_s'] / 60}m left)#{Colors.reset}" if f['hold_remaining_s'].to_i.positive?
    s << "  #{Colors.c201}DRY RUN#{Colors.reset}" if f['dry_run']
    s << "  #{Colors.c196}error: #{f['error']}#{Colors.reset}" if f['error']
    conds = (f['conditions'] || []).map do |c|
      lvl = c['level'].nil? ? '--' : (c['level'] >= 100 ? c['level'].round.to_s : format('%.1f', c['level']))
      mark = c['demand'] ? "#{Colors.c39}*#{Colors.reset}" : ' '
      "#{c['metric']} #{lvl}#{mark}#{Colors.c244}[on>=#{c['on_above']} off<=#{c['off_below']}]#{Colors.reset}"
    end
    s << "   " << conds.join('  ') unless conds.empty?
    s
  end

  # Horizontal 24h strip: one cell per BUCKET_MINUTES, oldest left.
  def timeline(data, colors, cols)
    buckets = HOURS * 60 / BUCKET_MINUTES
    width = cols >= buckets * 2 + 8 ? 2 : 1
    now = Time.now.to_f
    start = now - HOURS * 3600
    span = BUCKET_MINUTES * 60.0

    co2 = Array.new(buckets) { [] }
    temp = Array.new(buckets) { [] }
    (data['readings'] || []).each do |r|
      i = ((r['ts'] - start) / span).floor
      next unless i.between?(0, buckets - 1)

      co2[i] << r['co2'] if r['co2']
      temp[i] << r['temp_f'] if r['temp_f']
    end

    switches = (data['events'] || []).select { |e| e['type'] == 'switch' && e['feature'] == 'cooling' }
    current_on = data.dig('status', 'features', 'cooling', 'on')
    ac = Array.new(buckets) do |i|
      t_end = start + (i + 1) * span
      last = switches.select { |e| e['ts'] <= t_end }.last
      on = last ? last['on'] : (switches.first ? !switches.first['on'] : current_on)
      t_start = t_end - span
      on || switches.any? { |e| e['on'] && e['ts'].between?(t_start, t_end) }
    end
    feedback = Array.new(buckets) { false }
    (data['events'] || []).each do |e|
      next unless e['type'] == 'feedback'

      i = ((e['ts'] - start) / span).floor
      feedback[i] = true if i.between?(0, buckets - 1)
    end

    label = +'       '
    hours_row = +''
    buckets.times do |i|
      t = Time.at(start + i * span)
      cell = t.min < BUCKET_MINUTES && (t.hour % 3).zero? ? t.strftime('%H').ljust(width) : ' ' * width
      hours_row << cell
    end
    row = lambda do |name, cells|
      "#{Colors.c244}#{name.ljust(7)}#{Colors.reset}#{cells.join}#{Colors.reset}"
    end
    co2_cells = co2.map do |v|
      avg = v.empty? ? nil : v.sum / v.size
      "#{co2_bg(avg, colors)}#{' ' * width}#{Colors.reset}"
    end
    ac_cells = ac.map { |on| on ? "#{Colors.c39}#{'▀' * width}#{Colors.reset}" : ' ' * width }
    temp_cells = temp.map do |v|
      next ' ' * width if v.empty?

      avg = v.sum / v.size
      c = avg >= 78 ? Colors.c203 : avg <= 66 ? Colors.c75 : Colors.c250
      width == 2 ? "#{c}#{(avg.round % 100).to_s.rjust(2)}#{Colors.reset}" : "#{c}•#{Colors.reset}"
    end
    fb_cells = feedback.map { |f| f ? "#{Colors.c214}#{'^'.ljust(width)}#{Colors.reset}" : ' ' * width }

    [
      "#{Colors.yellow_bold}Last 24h#{Colors.reset} #{Colors.c244}(#{BUCKET_MINUTES}m cells, now at right)#{Colors.reset}",
      "#{label}#{Colors.c244}#{hours_row}#{Colors.reset}",
      row.call('CO2', co2_cells),
      row.call('AC', ac_cells),
      row.call('Temp F', temp_cells),
      row.call('Notes', fb_cells),
    ].join("\n") + "\n"
  end

  def event_log(events, colors, max_lines)
    lines = events.reverse.filter_map do |e|
      t = Time.at(e['ts']).strftime('%a %H:%M')
      case e['type']
      when 'switch'
        verb = e['on'] ? "#{Colors.c39}ON #{Colors.reset}" : "#{Colors.c250}OFF#{Colors.reset}"
        prev = e['previous_state_s'] ? " #{Colors.c244}(after #{fmt_dur(e['previous_state_s'])} #{e['on'] ? 'off' : 'on'})#{Colors.reset}" : ''
        dry = e['dry_run'] ? " #{Colors.c201}[dry run]#{Colors.reset}" : ''
        "#{Colors.c244}#{t}#{Colors.reset}  #{e['feature']} #{verb} #{e['reason']}#{prev}#{dry}"
      when 'feedback'
        label = FEEDBACK_KEYS.values.find { |v, _| v == e['value'] }&.last || e['value']
        "#{Colors.c244}#{t}#{Colors.reset}  #{Colors.c214}Kim: #{label}#{Colors.reset}  " \
          "#{co2_color(e['co2'], colors)}co2 #{e['co2']}#{Colors.reset} #{e['temp_f']}F #{e['humidity']}% " \
          "#{Colors.c244}AC #{e.dig('features', 'cooling') ? 'on' : 'off'}#{Colors.reset}"
      when 'error'
        "#{Colors.c244}#{t}#{Colors.reset}  #{Colors.c196}#{e['feature']} error: #{e['message']}#{Colors.reset}"
      when 'start'
        "#{Colors.c244}#{t}  airctl started#{Colors.reset}"
      end
    end
    head = "#{Colors.yellow_bold}Events#{Colors.reset} #{Colors.c244}(newest first)#{Colors.reset}\n"
    body = lines.first(max_lines)
    head + (body.empty? ? "#{Colors.c244}  none in the last #{HOURS}h#{Colors.reset}\n" : body.join("\n") + "\n")
  end

  def fmt_dur(s)
    s < 3600 ? "#{s / 60}m" : "#{s / 3600}h#{(s % 3600) / 60}m"
  end
end
