class Oscillator
  attr_accessor :waveform
  def initialize(waveform, sample_rate)
    @waveform = waveform
    @sample_rate = sample_rate
  end

  def generate_wave(note_data, buffer_size)
    delta = 2.0 * Math::PI * note_data[:frequency] / @sample_rate
    Array.new(buffer_size) do
      sample =
        case waveform
        when :sine
          Math.sin(note_data[:phase])
        when :sawtooth
          2.0 * (note_data[:phase] / (2.0 * Math::PI)) - 1.0
        when :triangle
          2.0 * (2.0 * (note_data[:phase] / (2.0 * Math::PI) - 0.5).abs) - 1.0
        when :pulse
          note_data[:phase] < Math::PI ? 1.0 : -1.0
        when :square
          note_data[:phase] < Math::PI ? 0.5 : -0.5
        else
          0.0
        end
      note_data[:phase] += delta
      note_data[:phase] -= 2.0 * Math::PI if note_data[:phase] > 2.0 * Math::PI
      sample
    end
  end
end
