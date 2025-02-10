require_relative "vcf"
require_relative "oscillator"

class Synthesizer
  attr_accessor :active
  attr_reader :vcf

  def initialize(sample_rate, amplitude)
    @sample_rate = sample_rate
    @amplitude = amplitude
    @active_notes = {}
    @oscillator = Oscillator.new(:sawtooth, sample_rate)
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
      samples = samples.zip(@oscillator.generate_wave(note_data, buffer_size)).map { |s1, s2| s1 + s2 }
    end

    # 平均化して振幅を保つ
    samples.map! { |sample| @vcf.apply(sample) * (@amplitude / @active_notes.size) }
  end
end
