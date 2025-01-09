require 'unimidi'

def list_midi_devices
  puts "Available MIDI Input Devices:"
  UniMIDI::Input.list.each_with_index do |input, index|
    puts "#{index}) #{input.inspect}"
  end
end

def select_midi_device
  list_midi_devices
  print "Select a MIDI device by number: "
  $stdout.flush
  device_index = gets.chomp.to_i

  begin
    input = UniMIDI::Input.use(device_index)
    puts "Selected MIDI device: #{input.inspect}"
    input
  rescue
    puts "Invalid selection. Exiting."
    exit
  end
end

def monitor_midi_signals(input)
  puts "Listening for MIDI signals from #{input.inspect}..."
  puts "Press Ctrl+C to exit."

  loop do
    messages = input.gets
    messages.each do |message|
      timestamp = message[:timestamp]
      data = message[:data]

      # Active Sensing (254) を無視
      next if data[0] == 254

      puts "[#{timestamp}] #{data.inspect}"
    end
  rescue Interrupt
    puts "\nExiting MIDI monitor."
    exit
  end
end

begin
  input = select_midi_device
  monitor_midi_signals(input)
rescue Interrupt
  puts "\nExiting program."
end
