#!/usr/bin/env ruby

(0..15).each do |i|
  (0..15).each do |j|
    code = (i * 16 + j).to_s
    print "\u001b[38;5;#{code}m #{code.ljust(4)}"
  end
  puts "\u001b[0m"
end

puts

(0..15).each do |i|
  (0..15).each do |j|
    code = (i * 16 + j).to_s
    print "\u001b[48;5;#{code}m #{code.ljust(4)}"
  end
  puts "\u001b[0m"
end
