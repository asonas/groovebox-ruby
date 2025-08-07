require 'unimidi'
require 'ffi-portaudio'
require_relative '../lib/groovebox'
require_relative '../lib/note'
require_relative '../lib/vca'
require_relative '../lib/synthesizer'

SAMPLE_RATE = 44100
BUFFER_SIZE = 128

# CC numbers for ADSR control
ATTACK_CC = 71
DECAY_CC = 72
SUSTAIN_CC = 73
RELEASE_CC = 74
WAVEFORM_CC = 75  # For switching waveforms

# Waveform types
WAVEFORMS = [:sine, :square, :sawtooth, :triangle]
WAVEFORM_NAMES = {
  sine: "Sine Wave",
  square: "Square Wave",
  sawtooth: "Sawtooth Wave",
  triangle: "Triangle Wave",
}

# Parameter range limits
ATTACK_MIN = 0.001
ATTACK_MAX = 2.0
DECAY_MIN = 0.001
DECAY_MAX = 2.0
SUSTAIN_MIN = 0.0
SUSTAIN_MAX = 1.0
RELEASE_MIN = 0.001
RELEASE_MAX = 3.0

# Parameter increment/decrement step
ADSR_STEP = 0.01

class ADSRController
  attr_reader :groovebox, :synth

  def initialize
    @groovebox = Groovebox.new
    @active_notes = {}

    # Create synthesizer
    @synth = create_synth
    @groovebox.add_instrument(@synth)

    # Set up audio stream
    setup_audio_stream
  end

  def create_synth
    # Initialize with reduced volume (to prevent clipping)
    synth = Synthesizer.new(SAMPLE_RATE, 2500)  # Reduced amplitude from 1000 to 500
    synth.oscillator.waveform = :sawtooth

    # Initial ADSR settings
    synth.envelope.attack = 0.1    # Initial attack: 0.1 sec
    synth.envelope.decay = 0.2     # Initial decay: 0.2 sec
    synth.envelope.sustain = 0.7   # Initial sustain: 0.7 (70% of max volume)
    synth.envelope.release = 0.5   # Initial release: 0.5 sec

    synth
  end

  def setup_audio_stream
    @stream = VCA.new(@groovebox, SAMPLE_RATE, BUFFER_SIZE)
  end

  def shutdown
    @stream.close if @stream
  end

  def handle_midi_input(input)
    Thread.new do
      loop do
        m = input.gets

        m.each do |message|
          # Skip specific MIDI messages
          skip_midi_note = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
          next if message[:data][0] == 254 # Active Sensing
          next if skip_midi_note.include?(message[:data][1])

          data = message[:data]
          status_byte = data[0]

          case status_byte & 0xF0
          when 0x90 # Note On
            midi_note = data[1]
            velocity = data[2]

            if velocity > 0
              # Limit volume (40 as volume ratio ~0.31 or 40/127)
              handle_note_on(midi_note, 40)
            else
              handle_note_off(midi_note)
            end

          when 0x80 # Note Off
            midi_note = data[1]
            handle_note_off(midi_note)

          when 0xB0 # Control Change
            cc_number = data[1]
            cc_value = data[2]

            handle_cc(cc_number, cc_value)
          end
        end
      end
    end
  end

  def handle_note_on(midi_note, velocity)
    puts "Note On: #{midi_note}, Velocity: #{velocity}"
    @groovebox.sequencer_note_on(midi_note, velocity)
    @active_notes[midi_note] = true
  end

  def handle_note_off(midi_note)
    puts "Note Off: #{midi_note}"
    @groovebox.sequencer_note_off(midi_note)
    @active_notes.delete(midi_note)
  end

  def handle_cc(cc_number, cc_value)
    case cc_number
    when ATTACK_CC
      # Decrease if cc_value is 127, otherwise increase
      new_value = cc_value == 127 ? -ADSR_STEP : ADSR_STEP
      current_attack = @synth.envelope.attack
      new_attack = (current_attack + new_value).clamp(ATTACK_MIN, ATTACK_MAX)
      @synth.envelope.attack = new_attack
      puts "Control Change: CC #{cc_number} (Value: #{cc_value}) -> Attack: #{@synth.envelope.attack.round(3)} sec"
    when DECAY_CC
      # Decrease if cc_value is 127, otherwise increase
      new_value = cc_value == 127 ? -ADSR_STEP : ADSR_STEP
      current_decay = @synth.envelope.decay
      new_decay = (current_decay + new_value).clamp(DECAY_MIN, DECAY_MAX)
      @synth.envelope.decay = new_decay
      puts "Control Change: CC #{cc_number} (Value: #{cc_value}) -> Decay: #{@synth.envelope.decay.round(3)} sec"
    when SUSTAIN_CC
      # Decrease if cc_value is 127, otherwise increase
      new_value = cc_value == 127 ? -ADSR_STEP : ADSR_STEP
      current_sustain = @synth.envelope.sustain
      new_sustain = (current_sustain + new_value).clamp(SUSTAIN_MIN, SUSTAIN_MAX)
      @synth.envelope.sustain = new_sustain
      puts "Control Change: CC #{cc_number} (Value: #{cc_value}) -> Sustain: #{@synth.envelope.sustain.round(3)}"
    when RELEASE_CC
      # Decrease if cc_value is 127, otherwise increase
      new_value = cc_value == 127 ? -ADSR_STEP : ADSR_STEP
      current_release = @synth.envelope.release
      new_release = (current_release + new_value).clamp(RELEASE_MIN, RELEASE_MAX)
      @synth.envelope.release = new_release
      puts "Control Change: CC #{cc_number} (Value: #{cc_value}) -> Release: #{@synth.envelope.release.round(3)} sec"
    when WAVEFORM_CC
      # Select waveform from CC value (map 0-127 to 0-3)
      waveform_idx = (cc_value * WAVEFORMS.length / 128.0).to_i
      waveform = WAVEFORMS[waveform_idx]

      # Set waveform
      @synth.oscillator.waveform = waveform

      # Display selected waveform
      puts "Control Change: CC #{cc_number} (Value: #{cc_value}) -> Waveform: #{WAVEFORM_NAMES[waveform]}"

      display_current_settings
    end
  end

  def display_help
    puts "\nADSR Envelope Demo"
    puts "===================="
    puts "Waveform: #{WAVEFORM_NAMES[@synth.oscillator.waveform]} (default) - Can be changed with CC #{WAVEFORM_CC}"
    puts "CC #{ATTACK_CC}: Attack (decrease with value 127, increase with other values)"
    puts "CC #{DECAY_CC}: Decay (decrease with value 127, increase with other values)"
    puts "CC #{SUSTAIN_CC}: Sustain (decrease with value 127, increase with other values)"
    puts "CC #{RELEASE_CC}: Release (decrease with value 127, increase with other values)"
    puts "Play notes to check the sound."
    puts "Press Ctrl+C to exit."

    display_current_settings
  end

  def display_current_settings
    puts "\nCurrent ADSR Settings:"
    puts "Attack: #{@synth.envelope.attack.round(3)} sec"
    puts "Decay: #{@synth.envelope.decay.round(3)} sec"
    puts "Sustain: #{@synth.envelope.sustain.round(3)}"
    puts "Release: #{@synth.envelope.release.round(3)} sec"
    puts "Waveform: #{WAVEFORM_NAMES[@synth.oscillator.waveform]}"
  end
end

# Main program
begin
  FFI::PortAudio::API.Pa_Initialize

  puts "ADSR Envelope Demo"
  puts "===================="
  puts "Please select MIDI input..."
  input = UniMIDI::Input.gets
  puts "Selected: #{input.name}"

  # Create and start controller
  adsr_controller = ADSRController.new
  adsr_controller.display_help

  # Start MIDI processing
  adsr_controller.handle_midi_input(input)

  # Keep main thread alive
  loop { sleep 1 }

rescue Interrupt
  puts "\nShutting down..."
  adsr_controller&.shutdown
  input&.close
  FFI::PortAudio::API.Pa_Terminate
end
