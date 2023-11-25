require 'date'

class MedLogger
  # Make new private to prevent external instantiation
  private_class_method :new

  # Method to provide a single instance of Logger
  def self.instance
    @instance ||= new
  end

  def initialize
    @current_date = Date.today
    open_log_file
    delete_old_logs
  end

  # Method to open a log file based on the current date with the specified naming convention
  def open_log_file
    date_str = @current_date.strftime('%Y%m%d')
    @log_file = File.open("med_dash_#{date_str}.log", 'a')
  end

  # Method to add a log entry
  def log(message)
    check_date_change
    @log_file.puts("[#{Time.now}] #{message}")
    @log_file.flush
  end

  # Check if the date has changed, and open a new log file if it has
  def check_date_change
    if Date.today != @current_date
      @log_file.close unless @log_file.closed?
      @current_date = Date.today
      open_log_file
      delete_old_logs
    end
  end

  # Method to delete log files older than one week
  def delete_old_logs
    one_week_ago = (Date.today - 7).strftime('%Y%m%d')
    Dir.glob('med_dash_*.log').each do |file|
      file_date_str = file[/med_dash_(\d+)\.log/, 1]
      if file_date_str && file_date_str < one_week_ago
        File.delete(file)
      end
    end
  end

  # Method to close the log file
  def close
    @log_file.close unless @log_file.closed?
  end
end