require 'drb/drb'
require 'ffi-portaudio'
require 'unimidi'
require 'yaml'

SAMPLE_RATE = 44100
BUFFER_SIZE = 128
AMPLITUDE = 1000
BPM = 120
STEPS = 16

require_relative "lib/synthesizer"
require_relative "lib/note"
require_relative "lib/vca"
require_relative "lib/step"
require_relative "lib/presets/kick"

def handle_midi_signals(groovebox, sequencer_player, config)
  midi_input = UniMIDI::Input.use(config['midi_device']['index'])
  midi_output = UniMIDI::Output.use(config['midi_device']['index'])
  puts "Listening for MIDI signals from #{midi_input.name}..."

  white_keys = [0, 2, 4, 5, 7, 9, 11] # C, D, E, F, G, A, B
  drum_pad_range = (68..95).to_a

  loop do
    if groovebox.current_instrument.is_a?(DrumRack)
      drum_pad_range.each do |midi_note|
        if groovebox.current_instrument.pad_notes.include?(midi_note)
          midi_output.puts(0x90, midi_note, 120)
        else
          midi_output.puts(0x80, midi_note, 0)
        end
      end
    elsif groovebox.current_instrument.is_a?(Synthesizer)
      # 白鍵のパッドを光らせる
      (config['keyboard']['note_range']['start']..config['keyboard']['note_range']['end']).each do |midi_note|
        if white_keys.include?(midi_note % 12)
          midi_output.puts(0x90, midi_note, 120)
        else
          midi_output.puts(0x80, midi_note, 0)
        end
      end
    end

    midi_input.gets.each do |message|
      data = message[:data]
      # TODO: 254を受信出来なくなったらエラーを出して終了させる
      next if data[0] == 254 # Active Sensing を無視

      status_byte = data[0]
      midi_note = data[1]
      velocity = data[2]

      case status_byte & 0xF0
      when 0x90 # Note On (channel 0 => 0x90, channel 1 => 0x91, etc.)
        groovebox.current_instrument.note_on(midi_note, velocity)
        puts "Note On: ch=#{status_byte & 0x0F}, midi_note=#{midi_note}, velocity=#{velocity}"

      when 0x80 # Note Off
        groovebox.current_instrument.note_off(midi_note)
        puts "Note Off: ch=#{status_byte & 0x0F}, midi_note=#{midi_note}"
      when 0xB0 # Control Change (channel 0=>0xB0,1=>0xB1, etc.)
        control = midi_note
        value = velocity

        # LPF / HPF
        # cutoff_change = value == 127 ? 10 : -10
        # if control == 71
        #   synthesizer.vcf.low_pass_cutoff += cutoff_change
        #   puts "VCF Low Pass Cutoff: #{synthesizer.vcf.low_pass_cutoff.round(2)} Hz"
        # elsif control == 72
        #   synthesizer.vcf.high_pass_cutoff += cutoff_change
        #   puts "VCF High Pass Cutoff: #{synthesizer.vcf.high_pass_cutoff.round(2)} Hz"
        # end

        # ADSR
        # Attack: 0.00~2.00
        # Decay: 0.00~5.00
        # Sustain: 0.00~1.00
        # Release: 0.00~10.00
        case control
        when 73 # Attack
          new_value = value == 127 ? -0.01 : 0.01
          groovebox.current_instrument.envelope.attack =
            (groovebox.current_instrument.envelope.attack + new_value).clamp(0.00, 2.00)
          puts "Attack: #{groovebox.current_instrument.envelope.attack.round(2)}"
        when 74 # Decay
          new_value = value == 127 ? 0.01 : -0.01
          groovebox.current_instrument.envelope.decay = groovebox.current_instrument.envelope.decay.clamp(0.00, 5.00)
          puts "Decay: #{groovebox.current_instrument.envelope.decay.round(2)}"
        when 75 # Sustain
          new_value = value == 127 ? 0.01 : -0.01
          groovebox.current_instrument.envelope.sustain = groovebox.current_instrument.envelope.sustain.clamp(0.00, 1.00)
          puts "Sustain: #{groovebox.current_instrument.envelope.sustain.round(2)}"
        when 76 # Release
          new_value = value == 127 ? 0.01 : -0.01
          groovebox.current_instrument.envelope.release = groovebox.current_instrument.envelope.release.clamp(0.00, 10.00)
          puts "Release: #{groovebox.current_instrument.envelope.release.round(2)}"
        end

        case control
        when 40 # Channel Select
          groovebox.change_channel(3)
        when 41
          groovebox.change_channel(2)
        when 42
          groovebox.change_channel(1)
        when 43
          groovebox.change_channel(0)
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

# 規定のmidi_noteから4x4のドラムパッドを生成する
# basa_midi_noteが68で4x8のデバイスの場合は以下のようにアサインされる
# 92 93 94 95
# 84 85 86 87
# 76 77 78 79
# 68 69 70 71
class DrumRack
  MAX_TRACKS = 16

  def initialize(base_midi_node)
    @tracks = {}
    @base_midi_node = base_midi_node
  end

  def add_track(synth, pad_offset = 0)
    midi_note = @base_midi_node + pad_offset
    @tracks[midi_note] = synth
  end

  def note_on(midi_note, velocity)
    if @tracks[midi_note]
      @tracks[midi_note].note_on(midi_note, velocity)
      puts "Note On: #{midi_note}, velocity=#{velocity}"
    end
  end

  def note_off(midi_note)
    if @tracks[midi_note]
      @tracks[midi_note].note_off(midi_note)
      puts "Note Off: #{midi_note}"
    end
  end

  def generate(buffer_size)
    mixed_samples = Array.new(buffer_size, 0.0)
    active_tracks = 0

    @tracks.each do |midi_note, synth|
      samples = synth.generate(buffer_size)
      next if samples.all? { |sample| sample.zero? }

      mixed_samples = mixed_samples.zip(samples).map { |a, b| a + b }
      active_tracks += 1
    end
    gain_adjustment = active_tracks > 0 ? 1.0 / active_tracks : 1.0
    mixed_samples.map! { |sample| sample * gain_adjustment }

    mixed_samples
  end

  def pad_notes
    @tracks.keys
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

class Groovebox
  def initialize
    @instruments = []
    @current_channel = 0
  end

  def add_instrument(instrument)
    @instruments.push instrument
  end

  def change_channel(channel)
    @current_channel = channel
  end

  def current_instrument
    @instruments[@current_channel]
  end

  def note_on(midi_note, velocity)
    current_instrument.note_on(midi_note, velocity)
  end

  def note_off(midi_note)
    current_instrument.note_off(midi_note)
  end

  def generate(frame_count)
    current_instrument.generate(frame_count)
  end
end

begin
  config = YAML.load_file('midi_config.yml')

  groovebox = Groovebox.new

  synthesizer = Synthesizer.new(SAMPLE_RATE, AMPLITUDE)
  groovebox.add_instrument synthesizer

  kick = Presets::Kick.new
  drum_rack = DrumRack.new(68)
  drum_rack.add_track(kick, 0)

  groovebox.add_instrument drum_rack

  stream = VCA.new(groovebox, SAMPLE_RATE, BUFFER_SIZE)

  DRb.start_service
  sequencer = DRbObject.new_with_uri('druby://localhost:8787')

  sequencer_player = SequencerPlayer.new(kick, sequencer)

  puts "Playing sound. Use MIDI to control:"
  puts "  MIDI: Note range #{config['keyboard']['note_range']['start']} - #{config['keyboard']['note_range']['end']}"
  Thread.new do
    handle_midi_signals(groovebox, sequencer_player, config)
  end

  DRb.thread.join
ensure
  stream&.close
  FFI::PortAudio::API.Pa_Terminate
end
