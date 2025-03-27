require 'drb/drb'
require 'ffi-portaudio'
require 'unimidi'
require 'yaml'

SAMPLE_RATE = 44100
BUFFER_SIZE = 128
AMPLITUDE = 1000
BPM = 120
STEPS = 16

require_relative "lib/groovebox"
require_relative "lib/drum_rack"
require_relative "lib/synthesizer"
require_relative "lib/note"
require_relative "lib/vca"
require_relative "lib/step"

require_relative "lib/presets/bass"
require_relative "lib/presets/kick"
require_relative "lib/presets/snare"
require_relative "lib/presets/hihat_closed"
require_relative "lib/presets/piano"
require_relative "lib/sidechain"

def handle_midi_signals(groovebox, config)
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

        # サイドチェインパラメータの調整
        case control
        when 77 # サイドチェインのThreshold
          if groovebox.instance_variable_defined?(:@sidechain_connections) && !groovebox.instance_variable_get(:@sidechain_connections).empty?
            # シンセサイザーに適用されているサイドチェイン
            sidechain_connection = groovebox.instance_variable_get(:@sidechain_connections)[0]
            if sidechain_connection
              sidechain = sidechain_connection[:processor]
              new_value = value == 127 ? -0.01 : 0.01
              sidechain.threshold = (sidechain.threshold + new_value).clamp(0.01, 0.9)
              puts "サイドチェイン Threshold: #{sidechain.threshold.round(2)}"
            end
          end
        when 78 # サイドチェインのRelease
          if groovebox.instance_variable_defined?(:@sidechain_connections) && !groovebox.instance_variable_get(:@sidechain_connections).empty?
            # シンセサイザーに適用されているサイドチェイン
            sidechain_connection = groovebox.instance_variable_get(:@sidechain_connections)[0]
            if sidechain_connection
              sidechain = sidechain_connection[:processor]
              new_value = value == 127 ? -0.01 : 0.01
              sidechain.release = (sidechain.release + new_value).clamp(0.01, 1.0)
              puts "サイドチェイン Release: #{sidechain.release.round(2)}"
            end
          end
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

  groovebox = Groovebox.new

  synthesizer = Synthesizer.new(SAMPLE_RATE, AMPLITUDE)
  groovebox.add_instrument synthesizer

  bass = Presets::Bass.new
  groovebox.add_instrument bass

  piano = Presets::Piano.new
  groovebox.add_instrument piano

  kick = Presets::Kick.new
  drum_rack = DrumRack.new(68)
  drum_rack.add_track(kick, 0, 1.2)

  snare = Presets::Snare.new
  drum_rack.add_track(snare, 1, 1.0)

  hihat_closed = Presets::HihatClosed.new
  drum_rack.add_track(hihat_closed, 2, 0.5)

  groovebox.add_instrument drum_rack

  # サイドチェインの設定: キック（ドラムラック）をトリガーとして、シンセサイザーの音量を制御
  groovebox.setup_sidechain(1, 0, {
    threshold: 0.2,
    attack: 0.001,
    release: 0.2,
    ratio: 8.0,
  })

  # ベースシンセ用のサイドチェインの設定
  groovebox.setup_sidechain(2, 0, {
    threshold: 0.2,
    attack: 0.001,
    release: 0.2,
    ratio: 8.0,
  })

  stream = VCA.new(groovebox, SAMPLE_RATE, BUFFER_SIZE)

  # Grooveboxをdrubyサーバーとして公開
  DRb.start_service('druby://localhost:8786', groovebox)
  puts "Groovebox DRb server running at druby://localhost:8786"

  puts "Playing sound. Use MIDI to control:"
  puts "  MIDI: Note range #{config['keyboard']['note_range']['start']} - #{config['keyboard']['note_range']['end']}"
  Thread.new do
    # TODO: configは渡さないようにする
    # MIDI機器が見つからなかった場合は、代替のデバイスを探すUIを表示する
    handle_midi_signals(groovebox, config)
  end

  DRb.thread.join
ensure
  stream&.close
  FFI::PortAudio::API.Pa_Terminate
end
