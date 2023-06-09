# frozen_string_literal: true

# Class to query imessage sqlite db and pulls files from a particular chat
#
class IMessageChatDB
  # @@query_history = 4 * 86400
  @@query_history = 86_400 * 2
  @@reset_time = 5

  def initialize
    @db_path = "#{ENV['HOME']}/Library/Messages/chat.db"

    return if File.readable?(@db_path)

    raise "status=ERROR error=FILE_READ file=#{@db_path}"
  end

  def chat_id
    app_path = File.dirname($PROGRAM_NAME)

    chat_id_path = "#{app_path}/chatid"
    if File.readable?(chat_id_path)
      File.read(chat_id_path).strip
    else
      # donalds chatid
      'chat574232935236064109'
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
      if !result[5].nil?
        result[6] = nil
        result
      elsif result[6].nil?
        result
      else
        attributed_body = result[6].force_encoding('UTF-8').encode('UTF-8', invalid: :replace)

        # puts "unicodebody: #{attributed_body}"

        if attributed_body.include?('NSNumber')
          attributed_body = attributed_body.split('NSNumber')[0]
          if attributed_body.include?('NSString')
            attributed_body = attributed_body.split('NSString')[1]
            if attributed_body.include?('NSDictionary')
              attributed_body = attributed_body.split('NSDictionary')[0]
              attributed_body = attributed_body[6..-13]

              result[5] = if attributed_body =~ /^.\u0000/
                            attributed_body.gsub(/^.\u0000/, '')
                          else
                            attributed_body
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
    str = ''
    get.map do |r|
      str += "========\n#{r[5]}\n"
    end
    str
  end
end
