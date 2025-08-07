# PicoRuby Sequencer - Main program
puts "PicoRuby Sequencer starting..."

# Constants
BPM = 120
STEPS = 16
TRACKS = 4
LED_PIN = 25  # Raspberry Pi Pico onboard LED

# GPIO pins for output (LEDs or triggers)
OUTPUT_PINS = [2, 3, 4, 5]

# GPIO pins for buttons (step buttons)
BUTTON_PINS = [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]

# Pattern storage (TRACKS × STEPS)
pattern = Array.new(TRACKS) { Array.new(STEPS, 0) }

# Initialize some default pattern
pattern[0][0] = 1  # Kick on step 1
pattern[0][8] = 1  # Kick on step 9
pattern[1][4] = 1  # Snare on step 5
pattern[1][12] = 1 # Snare on step 13
pattern[2][2] = 1  # Hi-hat on step 3
pattern[2][6] = 1  # Hi-hat on step 7
pattern[2][10] = 1 # Hi-hat on step 11
pattern[2][14] = 1 # Hi-hat on step 15

# Initialize GPIO
GPIO.set_mode(LED_PIN, GPIO::OUT)

OUTPUT_PINS.each do |pin|
  GPIO.set_mode(pin, GPIO::OUT)
end

BUTTON_PINS.each do |pin|
  GPIO.set_mode(pin, GPIO::IN_PULL_UP)
end

# Calculate timing
step_time_ms = (60.0 / BPM / 4) * 1000  # 16th notes

# Current step position
current_step = 0

# Main sequencer loop
loop do
  # Turn on LED for current step
  GPIO.digital_write(LED_PIN, 1)

  # Process current step for each track
  TRACKS.times do |track|
    if pattern[track][current_step] == 1
      # Trigger output for this track
      GPIO.digital_write(OUTPUT_PINS[track], 1)
    end
  end

  # Wait a short time for trigger pulse
  sleep_ms(10)

  # Turn off all outputs
  OUTPUT_PINS.each do |pin|
    GPIO.digital_write(pin, 0)
  end

  # Turn off LED
  GPIO.digital_write(LED_PIN, 0)

  # Wait for next step
  sleep_ms(step_time_ms.to_i - 10)

  # Move to next step
  current_step = (current_step + 1) % STEPS

  # Check button presses to toggle steps (simple polling)
  BUTTON_PINS.each_with_index do |pin, i|
    if GPIO.digital_read(pin) == 0  # Button pressed (active low with pull-up)
      # Toggle step for track 0 (simplification - in reality would need track selection)
      pattern[0][i] = pattern[0][i] == 0 ? 1 : 0
      sleep_ms(20)  # Debounce
    end
  end
end
