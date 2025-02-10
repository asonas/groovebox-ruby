require 'drb/drb'
require 'ffi-portaudio'
require 'unimidi'
require 'yaml'

SAMPLE_RATE = 44100
BUFFER_SIZE = 1024
AMPLITUDE = 100
BPM = 120
STEPS = 16

# 音階管理クラス
class Note
  BASE_FREQUENCY = 440.0
  NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze

  def initialize
    @semitone = 0
  end

  def frequency
    BASE_FREQUENCY * (2 ** (@semitone / 12.0))
  end

  def set_by_name(name)
    note_index = NOTE_NAMES.index(name[0..-2]) # 音階部分
    octave = name[-1].to_i
    @semitone = (octave - 4) * 12 + note_index - 9
    self
  end

  def name
    NOTE_NAMES[(@semitone + 9) % 12]
  end

  def octave
    4 + ((@semitone + 9) / 12)
  end

  def display
    "#{name}#{octave} (#{frequency.round(2)} Hz)"
  end
end

class VCF
  attr_accessor :low_pass_cutoff, :high_pass_cutoff

  def initialize(sample_rate)
    @sample_rate = sample_rate
    @low_pass_cutoff = 1000.0
    @high_pass_cutoff = 100.0
    reset_filters
  end

  def apply(input)
    low_pass(high_pass(input))
  end

  def low_pass_cutoff=(new_frequency)
    @low_pass_cutoff = [[new_frequency, 20.0].max, @sample_rate / 2.0].min
    update_low_pass_alpha
  end

  def high_pass_cutoff=(new_frequency)
    @high_pass_cutoff = [[new_frequency, 20.0].max, @sample_rate / 2.0].min
    update_high_pass_alpha
  end

  private

  def reset_filters
    @low_pass_prev_output = 0.0
    @high_pass_prev_input = 0.0
    @high_pass_prev_output = 0.0
    update_low_pass_alpha
    update_high_pass_alpha
  end

  def update_low_pass_alpha
    rc = 1.0 / (2.0 * Math::PI * @low_pass_cutoff)
    @low_pass_alpha = rc / (rc + 1.0 / @sample_rate)
  end

  def update_high_pass_alpha
    rc = 1.0 / (2.0 * Math::PI * @high_pass_cutoff)
    @high_pass_alpha = rc / (rc + 1.0 / @sample_rate)
  end

  def low_pass(input)
    output = @low_pass_alpha * input + (1 - @low_pass_alpha) * @low_pass_prev_output
    @low_pass_prev_output = output
    output
  end

  def high_pass(input)
    output = (1 - @high_pass_alpha) * (@high_pass_prev_output + input - @high_pass_prev_input)
    @high_pass_prev_input = input
    @high_pass_prev_output = output
    output
  end
end

# 波形生成器クラス（VCO）
class Oscillator
  attr_accessor :waveform, :active
  attr_reader :vcf

  def initialize(sample_rate, amplitude)
    @sample_rate = sample_rate
    @amplitude = amplitude
    @waveform = :sawtooth
    @active_notes = {}
    @vcf = VCF.new(sample_rate)
  end

  def note_on(note, frequency)
    @active_notes[note] = { frequency: frequency, phase: 0.0 }
  end

  def note_off(note)
    @active_notes.delete(note)
  end

  def generate(buffer_size)
    return Array.new(buffer_size, 0.0) if @active_notes.empty?

    # 各ノートの波形を合成
    samples = Array.new(buffer_size, 0.0)
    @active_notes.each_value do |note_data|
      samples = samples.zip(generate_wave(note_data, buffer_size)).map { |s1, s2| s1 + s2 }
    end

    # 平均化して振幅を保つ
    samples.map! { |sample| @vcf.apply(sample) * (@amplitude / @active_notes.size) }
  end

  private

  def generate_wave(note_data, buffer_size)
    delta = 2.0 * Math::PI * note_data[:frequency] / @sample_rate
    Array.new(buffer_size) do
      sample =
        case @waveform
        when :sine then Math.sin(note_data[:phase])
        when :sawtooth then 2.0 * (note_data[:phase] / (2.0 * Math::PI)) - 1.0
        when :triangle then 2.0 * (2.0 * (note_data[:phase] / (2.0 * Math::PI) - 0.5).abs) - 1.0
        when :pulse then note_data[:phase] < Math::PI ? 1.0 : -1.0
        when :square then note_data[:phase] < Math::PI ? 0.5 : -0.5
        else 0.0
        end
      note_data[:phase] += delta
      note_data[:phase] -= 2.0 * Math::PI if note_data[:phase] > 2.0 * Math::PI
      sample
    end
  end
end

class AudioStream < FFI::PortAudio::Stream
  include FFI::PortAudio

  def initialize(generator, sample_rate, buffer_size)
    @generator = generator
    @buffer_size = buffer_size

    output_params = API::PaStreamParameters.new
    output_params[:device] = API.Pa_GetDefaultOutputDevice
    output_params[:channelCount] = 1
    output_params[:sampleFormat] = API::Float32
    output_params[:suggestedLatency] = API.Pa_GetDeviceInfo(output_params[:device])[:defaultHighOutputLatency]
    output_params[:hostApiSpecificStreamInfo] = nil

    super()
    open(nil, output_params, sample_rate, buffer_size)
    start
  end

  def process(input, output, frame_count, time_info, status_flags, user_data)
    samples = @generator.generate(frame_count)
    output.write_array_of_float(samples)
    :paContinue
  end
end

# MIDI信号監視スレッド
def monitor_midi_signals(generator, note, config)
  Thread.new do
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
              generator.note_on(midi_note, frequency)
              puts "Note On: #{Note::NOTE_NAMES[(midi_note % 12)]} (#{frequency.round(2)} Hz)"
            elsif config['switches'].key?(midi_note.to_s)
              generator.waveform = config['switches'][midi_note.to_s].to_sym
              puts "Waveform changed to: #{generator.waveform.capitalize}"
            end
          end
        when 0x80, 0x90 # Note Off or Note On with velocity 0
          midi_note = data[1]
          if (config['keyboard']['note_range']['start']..config['keyboard']['note_range']['end']).include?(midi_note)
            generator.note_off(midi_note)
            puts "Note Off: #{Note::NOTE_NAMES[(midi_note % 12)]}"
          end
        when 0xB0 # Control Change
          control = data[1]
          value = data[2]
          cutoff_change = value == 127 ? 10 : -10
          if control == 71
            generator.vcf.low_pass_cutoff += cutoff_change
            puts "VCF Low Pass Cutoff: #{generator.vcf.low_pass_cutoff.round(2)} Hz"
          elsif control == 74
            generator.vcf.high_pass_cutoff += cutoff_change
            puts "VCF High Pass Cutoff: #{generator.vcf.high_pass_cutoff.round(2)} Hz"
          end
        end
      end
    end
  end
end

class SequencerPlayer
  def initialize(generator, sequencer)
    @generator = generator
    @sequencer = sequencer
  end

  def play
    step_interval = 60.0 / BPM / STEPS
    loop do
      steps = @sequencer.steps
      steps.each_with_index do |step, index|
        if step.active
          note = Note.new.set_by_name(step.note)
          @generator.note_on(index, note.frequency)
          sleep step_interval
          @generator.note_off(index)
        else
          sleep step_interval
        end
      end
    end
  end
end

class Step
  attr_accessor :active, :note, :velocity

  def initialize(active: false, note: "C4", velocity: 127)
    @active = active
    @note = note
    @velocity = velocity
  end
end

# メイン処理
FFI::PortAudio::API.Pa_Initialize

begin
  config = YAML.load_file('midi_config.yml')
  generator = Oscillator.new(SAMPLE_RATE, AMPLITUDE)
  stream = AudioStream.new(generator, SAMPLE_RATE, BUFFER_SIZE)

  #puts "Playing sound. Use MIDI to control:"
  #puts "  MIDI: Note range #{config['keyboard']['note_range']['start']} - #{config['keyboard']['note_range']['end']}"
  #monitor_midi_signals(generator, nil, config)

  DRb.start_service
  sequencer = DRbObject.new_with_uri('druby://localhost:8787')

  puts "Connected to sequencer. Playing sequence..."

  player = SequencerPlayer.new(generator, sequencer)
  player.play

  #sleep
ensure
  stream&.close
  FFI::PortAudio::API.Pa_Terminate
end
