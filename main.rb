require 'drb/drb'
require 'ffi-portaudio'
require 'unimidi'
require 'yaml'

SAMPLE_RATE = 48000
BUFFER_SIZE = 512
AMPLITUDE = 100
BPM = 120
STEPS = 16

require_relative "lib/synthesizer"
require_relative "lib/note"
require_relative "lib/vca"
require_relative "lib/step"

def monitor_midi_signals(synthesizer, sequencer_player, config)
  midi_input = UniMIDI::Input.use(config['midi_device']['index'])
  puts "Listening for MIDI signals from #{midi_input.name}..."
  loop do
    midi_input.gets.each do |message|
      data = message[:data]
      next if data[0] == 254 # Active Sensing を無視

      case data[0] & 0xF0
      when 0x90 # Note On
        midi_note = data[1]
        velocity = data[2]
        if velocity > 0
          if (config['keyboard']['note_range']['start']..config['keyboard']['note_range']['end']).include?(midi_note)
            frequency = 440.0 * (2 ** ((midi_note - 69) / 12.0))
            synthesizer.note_on(midi_note, frequency)
            puts "Note On: #{Note::NOTE_NAMES[(midi_note % 12)]} (#{frequency.round(2)} Hz)"
          elsif config['switches'].key?(midi_note.to_s)
            synthesizer.oscillator.waveform = config['switches'][midi_note.to_s].to_sym
            puts "Waveform changed to: #{synthesizer.oscillator.waveform.capitalize}"
          end
        end
      when 0x80 # Note Off or Note On with velocity 0
        midi_note = data[1]
        if (config['keyboard']['note_range']['start']..config['keyboard']['note_range']['end']).include?(midi_note)
          synthesizer.note_off(midi_note)
          puts "Note Off: #{Note::NOTE_NAMES[(midi_note % 12)]}"
        end
      when 0xB0 # Control Change
        control = data[1]
        value = data[2]
        cutoff_change = value == 127 ? 10 : -10
        if control == 71
          synthesizer.vcf.low_pass_cutoff += cutoff_change
          puts "VCF Low Pass Cutoff: #{synthesizer.vcf.low_pass_cutoff.round(2)} Hz"
        elsif control == 74
          synthesizer.vcf.high_pass_cutoff += cutoff_change
          puts "VCF High Pass Cutoff: #{synthesizer.vcf.high_pass_cutoff.round(2)} Hz"
        end

        if control == config['start'] && value == 127
          Thread.new do
            sequencer_player.play
          end
        elsif control == config['stop'] && value == 127
          sequencer_player.stop
        end
      end
    end
  end
end

class SequencerPlayer
  def initialize(synthesizer, sequencer)
    @synthesizer = synthesizer
    @sequencer = sequencer
    @active = false
  end

  def play
    # 再生中にもう一度再生すると停止する
    current_status = @active
    @active = !current_status

    step_interval = 60.0 / BPM / STEPS

    while @active
      steps = @sequencer.steps
      steps.each_with_index do |step, index|
        if step.active
          note = Note.new.set_by_name(step.note)
          @synthesizer.note_on(index, note.frequency)
          sleep step_interval
          @synthesizer.note_off(index)
        else
          sleep step_interval
        end
      end
    end
  end

  def stop
    @active = false
  end
end

FFI::PortAudio::API.Pa_Initialize

begin
  config = YAML.load_file('midi_config.yml')
  synthesizer = Synthesizer.new(SAMPLE_RATE, AMPLITUDE)
  stream = VCA.new(synthesizer, SAMPLE_RATE, BUFFER_SIZE)

  DRb.start_service
  sequencer = DRbObject.new_with_uri('druby://localhost:8787')

  sequencer_player = SequencerPlayer.new(synthesizer, sequencer)

  puts "Playing sound. Use MIDI to control:"
  puts "  MIDI: Note range #{config['keyboard']['note_range']['start']} - #{config['keyboard']['note_range']['end']}"
  monitor_midi_signals(synthesizer, sequencer_player, config)

  DRb.thread.join
ensure
  stream&.close
  FFI::PortAudio::API.Pa_Terminate
end
