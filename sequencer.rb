require 'io/console'
require 'drb/drb'

STEPS = 16
NOTE = "C4"
VELOCITY = 127

class Step
  attr_accessor :active, :note, :velocity

  def initialize(active: false, note: NOTE, velocity: VELOCITY)
    @active = active
    @note = note
    @velocity = velocity
  end
end

class Sequencer
  attr_reader :steps

  def initialize
    @steps = Array.new(STEPS) { Step.new }
    @current_position = 0
  end

  def toggle_step(index)
    @steps[index].active = !@steps[index].active
  end

  def display
    system('clear')
    puts (1..STEPS).map { |n| n.to_s.rjust(3) }.join
    puts @steps.map.with_index { |step, idx| idx == @current_position ? (step.active ? "[x]" : "[_]") : (step.active ? "[x]" : "[ ]") }.join
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
            @current_position += 1 if @current_position < STEPS - 1
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

sequencer = Sequencer.new
DRb.start_service('druby://localhost:8787', sequencer)
puts "Sequencer DRb server running at druby://localhost:8787"

sequencer.run
DRb.thread.join
