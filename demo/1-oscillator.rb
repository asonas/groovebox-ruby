require 'unimidi'
require 'ffi-portaudio'
require_relative '../lib/groovebox'
require_relative '../lib/note'
require_relative '../lib/vca'
require_relative '../lib/synthesizer'

SAMPLE_RATE = 44100
BUFFER_SIZE = 128

CONTROL_CCS = [40, 41, 42, 43]

def handle_midi_signals(groovebox, midi_input)
  loop do
    m = midi_input.gets

    m.each do |message|
      # Ignore spurious Note On messages from Ableton Move pads used for CC.
      skip_midi_note = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
      next if skip_midi_note.include?(message[:data][1])

      data = message[:data]
      next if data[0] == 254 # Active Sending

      status_byte = data[0]

      case status_byte & 0xF0
      when 0x90 # Note On
        midi_note = data[1]
        velocity = data[2]
        if velocity > 0
          puts "Note On: #{midi_note}, Velocity: #{velocity}"
          groovebox.sequencer_note_on(midi_note, 50)
        else
          puts "Note Off (from Note On msg): #{midi_note}"
          groovebox.sequencer_note_off(midi_note)
        end
      when 0x80 # Note Off
        midi_note = data[1]
        puts "Note Off: #{midi_note}"
        groovebox.sequencer_note_off(midi_note)
      when 0xB0 # Control Change
        cc_number = data[1]
        cc_value = data[2]

        if CONTROL_CCS.include?(cc_number) && cc_value > 0
          waveform =
            case cc_number
            when 40 then :sine
            when 41 then :sawtooth
            when 42 then :triangle
            when 43 then :square
            end

          if waveform
            puts "Control Change: CC #{cc_number} -> Waveform: #{waveform}"
            groovebox.current_instrument.oscillator.waveform = waveform
          end
        end
      end
    end
  end
end

begin
  FFI::PortAudio::API.Pa_Initialize

  input = UniMIDI::Input.gets

  groovebox = Groovebox.new

  synth = Synthesizer.new(SAMPLE_RATE, 100)
  groovebox.add_instrument(synth)

  stream = VCA.new(groovebox, SAMPLE_RATE, BUFFER_SIZE)

  Thread.new do
    handle_midi_signals(groovebox, input)
  end

  loop { sleep 1 }

rescue Interrupt
  stream.close
  input.close
  FFI::PortAudio::API.Pa_Terminate
end
