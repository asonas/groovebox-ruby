require_relative "vcf"
require_relative "oscillator"
require_relative "envelope"

class Synthesizer
  attr_accessor :active, :envelope
  attr_reader :vcf

  def initialize(sample_rate, amplitude)
    @sample_rate = sample_rate
    @amplitude = amplitude
    @active_notes = {}
    @oscillator = Oscillator.new(:sawtooth, sample_rate)
    @vcf = VCF.new(sample_rate)
    @envelope = Envelope.new
  end

  def note_on(note, frequency)
    @active_notes[note] = { frequency: frequency, phase: 0.0, note_on_time: Time.now, note_off_time: nil }
  end

  def note_off(note)
    if @active_notes[note]
      @active_notes[note][:note_off_time] = Time.now
    end
  end

  def generate(buffer_size)
    return Array.new(buffer_size, 0.0) if @active_notes.empty?

    # 個々の発音を合成する先
    samples = Array.new(buffer_size, 0.0)

    # すべてのノートを合成
    @active_notes.each_value do |note_data|
      wave = @oscillator.generate_wave(note_data, buffer_size)

      wave.each_with_index do |sample_val, idx|
        env_val = @envelope.apply_envelope(note_data, idx)
        wave[idx] = sample_val * env_val
        # wave[idx] = @vcf.apply(sample_val * env_val)
      end

      # 各ノートの波形を足し合わせるだけ
      samples = samples.zip(wave).map { |s1, s2| s1 + s2 }
    end

    # 固定のゲインをかける
    master_gain = 0.3
    samples.map! { |sample| sample * master_gain }

    # TODO: リリースノートのクリーンアップしたいがバグってる...
    cleanup_inactive_notes(buffer_size)

    samples
  end

  private

  def cleanup_inactive_notes(buffer_size)
    @active_notes.delete_if do |note_id, note_data|
      if note_data[:note_off_time]
        # バッファの最後のサンプルでエンベロープが0以下なら削除
        final_envelope = @envelope.apply_envelope(note_data, buffer_size - 1)
        final_envelope <= 0.0
      else
        false
      end
    end
  end
end
