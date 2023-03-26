#!/usr/bin/env ruby

require 'sqlite3'

db_path = "#{ENV['HOME']}/Library/Messages/chat.db"
db = SQLite3::Database.new(db_path)

unless File.readable?(db_path)
  raise "status=ERROR error=FILE_READ file=#{db_path}"
end

app_path = File.dirname($PROGRAM_NAME)

chat_id_path = "#{app_path}/chatid"
if File.readable?(chat_id_path)
  chat_id = File.read(chat_id_path).strip
else
  # donalds chatid
  chat_id = "chat574232935236064109"
end

db_query = "SELECT
    message.is_from_me,
    chat.chat_identifier,
    datetime (message.date / 1000000000 + strftime (\"%s\", \"2001-01-01\"), \"unixepoch\", \"localtime\") AS message_date,
    message.date / 1000000000 + strftime (\"%s\", \"2001-01-01\") AS message_epoch,
    strftime (\"%s\", \"now\") AS now_epoch,
    message.text
FROM
    chat
    JOIN chat_message_join ON chat. \"ROWID\" = chat_message_join.chat_id
    JOIN message ON chat_message_join.message_id = message. \"ROWID\"
WHERE
     chat.chat_identifier LIKE \"#{chat_id}\"
     AND (now_epoch-message_epoch) <= 86400
ORDER BY
    message_date ASC"

db_results = db.execute(db_query)

pp db_results

