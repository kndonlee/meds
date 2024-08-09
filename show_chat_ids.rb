#!/usr/bin/env ruby

require 'sqlite3'

db_path = "#{ENV['HOME']}/Library/Messages/chat.db"
db = SQLite3::Database.new(db_path)

unless File.readable?(db_path)
  raise "status=ERROR error=FILE_READ file=#{db_path}"
end

app_path = File.dirname($PROGRAM_NAME)

db_query="SELECT C.ROWID, C.chat_identifier, C.service_name, H.id
FROM chat C
JOIN chat_handle_join CHJ ON C.ROWID = CHJ.chat_id
JOIN handle H ON CHJ.handle_id = H.ROWID"

db_results = db.execute(db_query)

pp db_results
