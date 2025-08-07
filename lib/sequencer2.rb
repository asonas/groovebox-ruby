require 'unimidi'

puts "Available MIDI output ports:"
UniMIDI::Output.all.each_with_index do |port, i|
  puts "#{i}: #{port.name}"
end

port_index = 0 # ToDo: あとで選べるようにする
puts "Using device #{port_index}."

output_port = UniMIDI::Output.all[port_index]

unless output_port
  puts "No valid MIDI port found. Exiting."
  exit
end

puts "Opening #{output_port.name}..."

output = output_port.open

BPM = 100
STEPS_PER_BAR = 16
TOTAL_STEPS = STEPS_PER_BAR * 8  # 16 * 8 = 128 (8小節)
PARTS = 6  # volca drumの6パート
PARTS_ACTIVE_PROBABILITY = 0.3  # 各ステップで音が鳴る確率

def generate_sequence
  sequence = {}

  (1..PARTS).each do |channel|
    sequence[channel] = []

    # 1ステップごとに音を鳴らすかどうかをランダムに決める
    TOTAL_STEPS.times do |step|
      active = rand < PARTS_ACTIVE_PROBABILITY

      if active
        # volca drumのノートナンバーはC4 (60)に固定（音階は変わらない）、ベロシティはランダム
        note_number = 60
        velocity = rand(70..110)
        sequence[channel] << {
          step: step,
          note: note_number,
          velocity: velocity,
        }
      end
    end

    if channel == 1  # kick（Part 1）
      sequence[channel] = []
      # 4分音符の頭に多め
      TOTAL_STEPS.times do |step|
        if step % 4 == 0 && rand < 0.8
          sequence[channel] << {
            step: step,
            note: 60,
            velocity: rand(90..120),
          }
        elsif rand < 0.1
          sequence[channel] << {
            step: step,
            note: 60,
            velocity: rand(70..100),
          }
        end
      end
    elsif channel == 2 # snare
      sequence[channel] = []
      # 裏拍多め
      TOTAL_STEPS.times do |step|
        if (step % 8 == 4) && rand < 0.9
          sequence[channel] << {
            step: step,
            note: 60,
            velocity: rand(80..110),
          }
        elsif rand < 0.1
          sequence[channel] << {
            step: step,
            note: 60,
            velocity: rand(70..90),
          }
        end
      end
    elsif channel == 3
      sequence[channel] = []
      TOTAL_STEPS.times do |step|
        if step % 2 == 0 && rand < 0.7
          sequence[channel] << {
            step: step,
            note: 60,
            velocity: rand(50..90),
          }
        elsif rand < 0.3
          sequence[channel] << {
            step: step,
            note: 60,
            velocity: rand(40..70),
          }
        end
      end
    end
  end

  return sequence
end

require_relative 'periodic_cue'

def play_generative_sequence(output, sequence)
  step_interval = 60.0 / BPM / 4

  # PeriodicCueを設定（ノートオン時間とノートオフ時間の比率を管理）
  cue = PeriodicCue.new(step_interval * 0.8, step_interval * 0.2)
  cue.start

  puts "Starting generative sequence (BPM: #{BPM})..."
  puts "Press Ctrl+C to exit"

  current_step = 0

  begin
    loop do
      (1..PARTS).each do |channel|
        notes = sequence[channel].select { |note| note[:step] == current_step }

        notes.each do |note|
          # ノートオン
          puts "Part #{channel} Step #{current_step} Note On (Velocity: #{note[:velocity]})"
          output.puts(0x90 | (channel - 1), note[:note], note[:velocity])
        end
      end

      cue.sync

      (1..PARTS).each do |channel|
        notes = sequence[channel].select { |note| note[:step] == current_step }

        notes.each do |note|
          # ノートオフ
          output.puts(0x80 | (channel - 1), note[:note], 0)
        end
      end

      cue.sync

      current_step = (current_step + 1) % TOTAL_STEPS

      if current_step == 0
        sequence = generate_sequence
      end
    end
  rescue Interrupt
    puts "\nStopping sequence..."
    # すべてのノートをオフにする
    (1..PARTS).each do |channel|
      (0..127).each do |note|
        output.puts(0x80 | (channel - 1), note, 0)
      end
    end
  end
end

begin
  sequence = generate_sequence

  puts "\nGenerated sequence:"
  (1..PARTS).each do |channel|
    puts "Part #{channel}: #{sequence[channel].size} notes"
    sequence[channel].each do |note|
      puts "  Step #{note[:step]} - Note #{note[:note]} (Velocity: #{note[:velocity]})"
    end
  end

  puts "\nPlaying sequence..."
  play_generative_sequence(output, sequence)

rescue => e
  puts "An error occurred: #{e.message}"
  puts e.backtrace
ensure
  output.close if output
  puts "Port closed."
end
