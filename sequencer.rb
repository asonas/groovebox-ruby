require 'io/console'
require 'drb/drb'
require 'midilib'

require_relative "lib/step"

class Sequencer
  attr_reader :steps

  def initialize(mid_file_path = nil)
    @steps = []
    @current_position = 0

    if mid_file_path
      puts "Loading MIDI file: #{mid_file_path}"
      load_midi_file(mid_file_path)
    else
      @steps = Array.new(16) { Step.new }
    end
  end

  def load_midi_file(midi_file_path)
    seq = MIDI::Sequence.new

    File.open(midi_file_path, 'rb') do |file|
      seq.read(file)
    end

    track = seq.tracks[1]
    note_on_events = track.events.select do |event|
      event.kind_of?(MIDI::NoteOn) && event.velocity > 0
    end

    max_time = note_on_events.map(&:time_from_start).max
    ticks_per_step = seq.ppqn / 4.0
    total_steps = (max_time / ticks_per_step).ceil + 1
    @steps = Array.new(total_steps) { Step.new }

    note_on_events.each do |event|
      step_index = (event.time_from_start / ticks_per_step).to_i
      next if step_index >= @steps.size

      @steps[step_index].active = true
      @steps[step_index].note   = "MIDI#{event.note}"
    end
  end

  def toggle_step(index)
    @steps[index].active = !@steps[index].active
  end

  def display
    system('clear')
    puts (1..@steps.size).map { |n| n.to_s.rjust(3) }.join
    puts @steps.map.with_index { |step, idx|
      if idx == @current_position
        step.active ? "[#{step.note}]" : "[_]"
      else
        step.active ? "[#{step.note}]" : "[ ]"
      end
    }.join
    puts "Use arrow keys to move, Enter to toggle, Ctrl+C to exit."
  end

  def run
    loop do
      display
      case STDIN.getch
      when "\e" # Special keys
        if STDIN.getch == "["
          case STDIN.getch
          when "D" # Left arrow
            @current_position -= 1 if @current_position > 0
          when "C" # Right arrow
            @current_position += 1 if @current_position < @steps.size - 1
          end
        end
      when "\r" # Enter
        toggle_step(@current_position)
      when "\u0003" # Ctrl+C
        puts "Exiting..."
        break
      end
    end
  end
end

sequencer = Sequencer.new("./mekurume_prizm.mid")
DRb.start_service('druby://localhost:8787', sequencer)
puts "Sequencer DRb server running at druby://localhost:8787"

sequencer.run
DRb.thread.join
