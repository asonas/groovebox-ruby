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

def select_midi_device
  available_inputs = UniMIDI::Input.all
  available_inputs.each do |input|
    puts "MIDI Device: #{input.name} (index: #{available_inputs.index(input)})"
  end

  # Ableton Moveを自動検出して繋ぐ
  auto_selected_index = available_inputs.find_index { |input| input.name.include?('Ableton Move') }

  if auto_selected_index
    return auto_selected_index
  else
    selected_index = gets.chomp.to_i

    if selected_index < 0 || selected_index >= available_inputs.size
      return 0
    end

    return selected_index
  end
end

def handle_midi_signals(groovebox, config)
  # MIDIデバイスのインデックスを動的に選択
  midi_device_index = select_midi_device

  midi_input = UniMIDI::Input.use(midi_device_index)
  midi_output = UniMIDI::Output.use(midi_device_index)
  puts "MIDI Device: #{midi_input.name} (index: #{midi_device_index}) has been connected."

  white_keys = [0, 2, 4, 5, 7, 9, 11] # C, D, E, F, G, A, B
  drum_pad_range = (68..95).to_a

  # アクティブなノートを追跡するためのハッシュ
  active_notes = {}
  # 現在のインスツルメントのインデックスを記録
  current_instrument_index = groovebox.current_instrument_index

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

    if current_instrument_index != groovebox.current_instrument_index
      # すべてのアクティブなノートをオフにする
      active_notes.each do |midi_note, instrument_index|
        puts "音階変更: 前の音をオフにします - note=#{midi_note}"
        groovebox.get_instrument(instrument_index).note_off(midi_note)
      end
      # アクティブノートをクリア
      active_notes = {}
      # 現在のインスツルメントインデックスを更新
      current_instrument_index = groovebox.current_instrument_index
    end

    midi_input.gets.each do |message|
      data = message[:data]
      # TODO: 254を受信出来なくなったらエラーを出して終了させる
      next if data[0] == 254 # Active Sensing を無視

      status_byte = data[0]
      midi_note = data[1]
      velocity = data[2]

      # Ignore spurious Note On messages from Ableton Move pads used for CC.
      skip_mini_note = [0,1,2,3,4,5,6,7,8,9,10,11]

      case status_byte & 0xF0
      when 0x90 # Note On (channel 0 => 0x90, channel 1 => 0x91, etc.)
        next if skip_mini_note.include?(midi_note)
        groovebox.current_instrument.note_on(midi_note, velocity)

        # アクティブノートとして記録
        active_notes[midi_note] = groovebox.current_instrument_index
        puts "Note On: ch=#{status_byte & 0x0F}, midi_note=#{midi_note}, velocity=#{velocity}"

      when 0x80 # Note Off
        next if skip_mini_note.include?(midi_note)
        groovebox.current_instrument.note_off(midi_note)

        # アクティブノートから削除
        active_notes.delete(midi_note)
        puts "Note Off: ch=#{status_byte & 0x0F}, midi_note=#{midi_note}"
      when 0xB0 # Control Change (channel 0=>0xB0,1=>0xB1, etc.)
        control = midi_note
        value = velocity

        # TODO: リアルタイムで音作りをするよりも、コード上で音作りをする方が簡単になったので将来的に消す
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
        # case control
        # when 73 # Attack
        #   new_value = value == 127 ? -0.01 : 0.01
        #   groovebox.current_instrument.envelope.attack =
        #     (groovebox.current_instrument.envelope.attack + new_value).clamp(0.00, 2.00)
        #   puts "Attack: #{groovebox.current_instrument.envelope.attack.round(2)}"
        # when 74 # Decay
        #   new_value = value == 127 ? 0.01 : -0.01
        #   groovebox.current_instrument.envelope.decay = groovebox.current_instrument.envelope.decay.clamp(0.00, 5.00)
        #   puts "Decay: #{groovebox.current_instrument.envelope.decay.round(2)}"
        # when 75 # Sustain
        #   new_value = value == 127 ? 0.01 : -0.01
        #   groovebox.current_instrument.envelope.sustain = groovebox.current_instrument.envelope.sustain.clamp(0.00, 1.00)
        #   puts "Sustain: #{groovebox.current_instrument.envelope.sustain.round(2)}"
        # when 76 # Release
        #   new_value = value == 127 ? 0.01 : -0.01
        #   groovebox.current_instrument.envelope.release = groovebox.current_instrument.envelope.release.clamp(0.00, 10.00)
        #   puts "Release: #{groovebox.current_instrument.envelope.release.round(2)}"
        # end

        # サイドチェインパラメータの調整
        # case control
        # when 77 # サイドチェインのThreshold
        #   if groovebox.instance_variable_defined?(:@sidechain_connections) && !groovebox.instance_variable_get(:@sidechain_connections).empty?
        #     # シンセサイザーに適用されているサイドチェイン
        #     sidechain_connection = groovebox.instance_variable_get(:@sidechain_connections)[0]
        #     if sidechain_connection
        #       sidechain = sidechain_connection[:processor]
        #       new_value = value == 127 ? -0.01 : 0.01
        #       sidechain.threshold = (sidechain.threshold + new_value).clamp(0.01, 0.9)
        #       puts "サイドチェイン Threshold: #{sidechain.threshold.round(2)}"
        #     end
        #   end
        # when 78 # サイドチェインのRelease
        #   if groovebox.instance_variable_defined?(:@sidechain_connections) && !groovebox.instance_variable_get(:@sidechain_connections).empty?
        #     # シンセサイザーに適用されているサイドチェイン
        #     sidechain_connection = groovebox.instance_variable_get(:@sidechain_connections)[0]
        #     if sidechain_connection
        #       sidechain = sidechain_connection[:processor]
        #       new_value = value == 127 ? -0.01 : 0.01
        #       sidechain.release = (sidechain.release + new_value).clamp(0.01, 1.0)
        #       puts "サイドチェイン Release: #{sidechain.release.round(2)}"
        #     end
        #   end
        # end
        # TODO: ここまでが音作りの変更にまつわる実装

        case control
        when 40
          active_notes.each do |note, _|
            groovebox.current_instrument.note_off(note)
          end
          active_notes = {}
          groovebox.change_channel(3)
        when 41
          active_notes.each do |note, _|
            groovebox.current_instrument.note_off(note)
          end
          active_notes = {}
          groovebox.change_channel(2)
        when 42
          active_notes.each do |note, _|
            groovebox.current_instrument.note_off(note)
          end
          active_notes = {}
          groovebox.change_channel(1)
        when 43
          active_notes.each do |note, _|
            groovebox.current_instrument.note_off(note)
          end
          active_notes = {}
          groovebox.change_channel(0)
        end
      end
    end
  end
end

FFI::PortAudio::API.Pa_Initialize

begin
  config = YAML.load_file('midi_config.yml')

  groovebox = Groovebox.new

  piano = Presets::Piano.new
  groovebox.add_instrument piano

  synthesizer = Synthesizer.new(SAMPLE_RATE, AMPLITUDE)
  groovebox.add_instrument synthesizer

  bass = Presets::Bass.new
  groovebox.add_instrument bass

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

  DRb.start_service('druby://localhost:8786', groovebox)
  puts "Groovebox DRb server running at druby://localhost:8786"

  Thread.new do
    handle_midi_signals(groovebox, config)
  end

  DRb.thread.join
ensure
  stream&.close
  FFI::PortAudio::API.Pa_Terminate
end
