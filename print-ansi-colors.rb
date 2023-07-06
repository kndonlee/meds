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

puts

[70, 71, 72,73,74,75,69, 63,57,56,55,54,53].each do |i|
  code = i.to_s
  print "\u001b[48;5;#{code}m #{code.ljust(4)}"
  puts "\u001b[0m"

end
