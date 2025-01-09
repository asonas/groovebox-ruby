require 'ffi-portaudio'
require 'io/console'

SAMPLE_RATE = 44100
BUFFER_SIZE = 256
DEFAULT_FREQUENCY = 440.0  # A4
AMPLITUDE = 0.5

# 音階管理クラス
class Note
  BASE_FREQUENCY = 440.0 # A4
  NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze

  def initialize
    @semitone = 0 # A4を基準とした半音差
  end

  def frequency
    BASE_FREQUENCY * (2 ** (@semitone / 12.0))
  end

  def name
    NOTE_NAMES[(@semitone + 9) % 12] # C=0, A=9（モジュロ演算でループ）
  end

  def octave
    4 + ((@semitone + 9) / 12) # A4を基準にオクターブを計算
  end

  def increment
    @semitone += 1
  end

  def decrement
    @semitone -= 1
  end

  def display
    "#{name}#{octave} (#{frequency.round(2)} Hz)"
  end
end

# 波形生成器クラス（VCO）
class Oscillator
  attr_accessor :waveform

  def initialize(frequency, sample_rate, amplitude)
    @frequency = frequency
    @sample_rate = sample_rate
    @amplitude = amplitude
    @phase = 0.0
    update_delta
    @waveform = :sine # デフォルトはサイン波
  end

  def frequency=(new_frequency)
    @frequency = new_frequency
    update_delta
  end

  def generate(buffer_size)
    Array.new(buffer_size) { generate_sample }
  end

  private

  def update_delta
    @delta = 2.0 * Math::PI * @frequency / @sample_rate
  end

  def generate_sample
    case @waveform
    when :sine
      sample = Math.sin(@phase)
    when :sawtooth
      sample = 2.0 * (@phase / (2.0 * Math::PI)) - 1.0
    when :triangle
      sample = 2.0 * (2.0 * (@phase / (2.0 * Math::PI) - 0.5).abs) - 1.0
    when :pulse
      sample = @phase < Math::PI ? 1.0 : -1.0
    when :square
      sample = @phase < Math::PI ? 0.5 : -0.5
    else
      sample = 0.0
    end
    @phase += @delta
    @phase -= 2.0 * Math::PI if @phase > 2.0 * Math::PI
    sample * @amplitude
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

def monitor_keyboard(generator, note)
  Thread.new do
    loop do
      case STDIN.getch
      when 's'
        generator.waveform = :sine
        puts "Waveform changed to: Sine Wave"
      when 'n'
        generator.waveform = :sawtooth
        puts "Waveform changed to: Sawtooth Wave"
      when 't'
        generator.waveform = :triangle
        puts "Waveform changed to: Triangle Wave"
      when 'p'
        generator.waveform = :pulse
        puts "Waveform changed to: Pulse Wave"
      when 'k'
        generator.waveform = :square
        puts "Waveform changed to: Square Wave"
      when "\e"
        if STDIN.getch == '['
          case STDIN.getch
          when 'A' # ↑キー
            note.increment
            generator.frequency = note.frequency
            puts "Note changed to: #{note.display}"
          when 'B' # ↓キー
            note.decrement
            generator.frequency = note.frequency
            puts "Note changed to: #{note.display}"
          end
        end
      when "\u0003" # Ctrl+Cで終了
        exit
      end
    end
  end
end

FFI::PortAudio::API.Pa_Initialize

begin
  note = Note.new
  generator = Oscillator.new(note.frequency, SAMPLE_RATE, AMPLITUDE)
  stream = AudioStream.new(generator, SAMPLE_RATE, BUFFER_SIZE)

  puts "Playing sound. Press keys to control:"
  puts "  [s] Sine, [n] Sawtooth, [t] Triangle, [p] Pulse, [k] Square"
  puts "  [↑] Higher note, [↓] Lower note"
  monitor_keyboard(generator, note)

  sleep # 音声再生中（無限ループで待機）
ensure
  stream&.close
  FFI::PortAudio::API.Pa_Terminate
end
