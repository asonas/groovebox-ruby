module Presets
  class Cowbell < DrumSynthBase
    def initialize(sample_rate = 44100, amplitude = 1000, base_midi_note = 56, tune = 0)
      super(sample_rate, amplitude, base_midi_note, tune)

      # 808カウベルは2つの矩形波で構成
      @oscillator.waveform = :square

      # カウベル特有のエンベロープ
      @envelope.attack = 0.0
      @envelope.decay = 0.4
      @envelope.sustain = 0.0
      @envelope.release = 0.1
    end

    def generate(buffer_size)
      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      return samples if @active_notes.empty?

      @active_notes.each do |midi_note, note|
        note_on_index = note.note_on_sample_index
        time_since_note_on = (start_sample_index - note_on_index) / @sample_rate.to_f

        time_since_note_off = nil
        if note.note_off_sample_index
          time_since_note_off = (start_sample_index - note.note_off_sample_index) / @sample_rate.to_f
        end

        # 808カウベルの2つの周波数（完全5度）
        freq1 = note.frequency
        freq2 = note.frequency * 1.5  # 完全5度上

        buffer_size.times do |i|
          current_time = time_since_note_on + (i / @sample_rate.to_f)

          # 2つの矩形波
          square1 = (Math.sin(2.0 * Math::PI * freq1 * current_time) > 0) ? 1.0 : -1.0
          square2 = (Math.sin(2.0 * Math::PI * freq2 * current_time) > 0) ? 1.0 : -1.0

          # 混合（比率は808カウベルに近くなるように調整）
          combined = (square1 * 0.6) + (square2 * 0.4)

          # エンベロープ適用
          env_value = @envelope.at(current_time, time_since_note_off)

          value = combined * env_value * @amplitude * @velocity
          samples[i] += value
        end
      end

      # 軽いバンドパス処理
      filtered_samples = @vcf.process(samples, :low_pass)

      cleanup_inactive_notes(buffer_size)

      master_gain = 0.6
      filtered_samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size

      filtered_samples
    end

    private

    def cleanup_inactive_notes(buffer_size)
      current_time = @global_sample_count / @sample_rate.to_f
      buffer_duration = buffer_size / @sample_rate.to_f

      @active_notes.delete_if do |_, note|
        if note.note_off_sample_index
          time_since_note_off = current_time - (note.note_off_sample_index / @sample_rate.to_f)
          time_since_note_off > @envelope.release + buffer_duration
        else
          false
        end
      end
    end
  end
end
