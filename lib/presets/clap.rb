module Presets
  class Clap < Synthesizer
    attr_accessor :base_note

    def initialize
      super

      # 808クラップはバンドパスフィルターをかけたノイズ
      @oscillator.waveform = :noise

      # クラップ特有の複数の短いパルス
      @envelope.attack = 0.0
      @envelope.decay = 0.02
      @envelope.sustain = 0.0
      @envelope.release = 0.05  # リバーブ的な尾部のために少し長めに

      # バンドパスフィルター設定
      @vcf.low_pass_cutoff = 2000.0   # サンプルに合わせて調整
      @vcf.high_pass_cutoff = 500.0   # サンプルに合わせて調整

      # 基準となるMIDIノート
      @base_note = Note.new.set_by_midi(39)  # D#2
    end

    def note_on(midi_note, velocity)
      new_note = Note.new
      # クラップは固定周波数を使用
      new_note.set_by_midi(@base_note.midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      @active_notes[midi_note] = new_note
      puts "clap note_on: #{midi_note}, velocity=#{velocity}"
    end

    def note_off(midi_note)
      super(midi_note)
    end

    def generate(buffer_size)
      start_sample_index = @global_sample_count
      samples = Array.new(buffer_size, 0.0)

      return samples if @active_notes.empty?

      @active_notes.each_value do |note|
        note_on_index = note.note_on_sample_index
        time_since_note_on = (start_sample_index - note_on_index) / @sample_rate.to_f

        time_since_note_off = nil
        if note.note_off_sample_index
          time_since_note_off = (start_sample_index - note.note_off_sample_index) / @sample_rate.to_f
        end

        # 808クラップの特徴的な複数パルス - サンプルに合わせて調整
        pulse_times = [0.0, 0.01, 0.02]  # 0ms, 10ms, 20ms にパルス
        pulse_amplitudes = [1.0, 0.7, 0.5]  # 各パルスの強さ

        # 減衰定数
        short_decay = 0.015   # 短いエンベロープの減衰定数（約15ms）
        long_decay = 0.05     # 長い「リバーブ」エンベロープの減衰定数（約50ms）

        # ノイズ波形を生成
        noise_wave = Array.new(buffer_size) { rand * 2.0 - 1.0 }

        # 複数パルスを適用した波形を生成
        pulse_wave = Array.new(buffer_size, 0.0)

        buffer_size.times do |i|
          current_time = time_since_note_on + (i / @sample_rate.to_f)

          # 複数パルスのエンベロープを重ね合わせ
          env = 0.0

          # ノートオフ後は処理しない
          if time_since_note_off.nil? || time_since_note_off < 0
            pulse_times.each_with_index do |pt, idx|
              if current_time >= pt && current_time < pt + 0.03  # 各パルス約30msの長さで減衰
                tau = current_time - pt
                # 短いパルスは指数関数的に減衰
                env += pulse_amplitudes[idx] * Math.exp(-tau / short_decay)
              end
            end

            # リバーブ的な長めの減衰（100ms程度まで）
            if current_time < 0.1
              env += 0.3 * Math.exp(-current_time / long_decay)
            end
          else
            # ノートオフ後の処理
            # リリース時間に応じて全体の音量を下げる
            if time_since_note_off < @envelope.release
              release_factor = 1.0 - (time_since_note_off / @envelope.release)

              pulse_times.each_with_index do |pt, idx|
                if current_time >= pt && current_time < pt + 0.03
                  tau = current_time - pt
                  env += pulse_amplitudes[idx] * Math.exp(-tau / short_decay) * release_factor
                end
              end

              if current_time < 0.1
                env += 0.3 * Math.exp(-current_time / long_decay) * release_factor
              end
            end
          end

          # 振幅は最大1.0にクリップ
          env = env > 1.0 ? 1.0 : env

          pulse_wave[i] = noise_wave[i] * env
        end

        # 各ノートの波形を足し合わせる
        samples = samples.zip(pulse_wave).map { |s1, s2| s1 + s2 }
      end

      # バンドパスフィルタ処理（ローパスとハイパスの両方を適用）
      filtered_samples = @vcf.process(samples, :low_pass)
      filtered_samples = @vcf.process(filtered_samples, :high_pass)

      # 全体のゲイン調整
      master_gain = 12.0
      filtered_samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      filtered_samples
    end

    private

    def cleanup_inactive_notes(buffer_size)
      @active_notes.delete_if do |_, note|
        if note.note_off_sample_index
          final_env = @envelope.apply_envelope(note, @global_sample_count - 1, @sample_rate)
          final_env <= 0.0
        else
          false
        end
      end
    end
  end
end
