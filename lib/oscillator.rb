class Oscillator
  attr_accessor :waveform, :harmonics

  def initialize(waveform, sample_rate)
    @waveform = waveform
    @sample_rate = sample_rate
    @harmonics = [
      # [ 倍音比, 振幅比 ]
      [1.0, 1.0],      # 基本波 (1倍音)
      [2.0, 0.5],      # 第2倍音
      # [3.0, 0.3],      # 第3倍音
    ]
  end

  def generate_wave(note_data, buffer_size)
    delta = 2.0 * Math::PI * note_data[:frequency] / @sample_rate

    Array.new(buffer_size) do
      # 各倍音ごとに合成
      sample_sum = 0.0
      @harmonics.each do |(harmonic_ratio, amplitude_ratio)|
        # 各倍音の周波数を n倍して波形を生成
        phase_for_harmonic = note_data[:phase] * harmonic_ratio

        # 波形選択 (waveform) は基本波形を使うが、倍音にも同じ波形を適用する
        partial_sample =
          case waveform
          when :sine
            Math.sin(phase_for_harmonic)
          when :sawtooth
            2.0 * (phase_for_harmonic / (2.0 * Math::PI) - (phase_for_harmonic / (2.0 * Math::PI)).floor) - 1.0
          when :triangle
            2.0 * (2.0 * ((phase_for_harmonic / (2.0 * Math::PI)) - 0.5).abs) - 1.0
          when :pulse
            (phase_for_harmonic % (2.0 * Math::PI)) < Math::PI ? 1.0 : -1.0
          when :square
            (phase_for_harmonic % (2.0 * Math::PI)) < Math::PI ? 0.5 : -0.5
          else
            0.0
          end

        sample_sum += partial_sample * amplitude_ratio
      end

      # 全倍音の合計をメインのsampleとして扱う
      note_data[:phase] += delta
      note_data[:phase] -= 2.0 * Math::PI if note_data[:phase] > 2.0 * Math::PI

      sample_sum
    end
  end
end
