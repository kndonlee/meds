#!/usr/bin/env ruby

$LOAD_PATH.unshift File.dirname(__FILE__)

require 'meds'

# Main program
$__my_dash = MedDash.new

def cleanup
  puts "Performing cleanup..."
  $__my_dash.cleanup
  puts "Cleanup completed."
end

Signal.trap("SIGINT") do
  puts "SIGINT received."
  cleanup
  exit
end

$__my_dash.run