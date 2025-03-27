module Presets
  class Piano < Synthesizer
    attr_accessor :base_note
    attr_accessor :filter_cutoff, :filter_resonance
    attr_accessor :brightness, :hardness
    attr_accessor :oscillators, :oscillator_mix

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      # ピアノらしいADSRエンベロープ設定
      # 速いアタック、中程度のディケイ、低めのサステイン、長めのリリース
      @envelope.attack = 0.001  # 非常に速いアタック
      @envelope.decay = 0.8     # ディケイは比較的長め
      @envelope.sustain = 0.2   # サステインレベルは低め
      @envelope.release = 0.5   # リリースは長め

      # メインオシレーター（親クラスから継承）の設定
      @oscillator.waveform = :triangle

      # メインオシレーターの倍音構造を再現
      @oscillator.harmonics = [
        [1.0, 1.0],    # 基本波（100%）
        [2.0, 0.5],    # 第2倍音（50%）
        [3.0, 0.3],    # 第3倍音（30%）
        [4.0, 0.2],    # 第4倍音（20%）
        [5.0, 0.1],    # 第5倍音（10%）
        [6.0, 0.05],   # 第6倍音（5%）
        [7.0, 0.025],  # 第7倍音（2.5%）
      ]

      # 追加のオシレーターを作成（音の厚みのため）
      @oscillators = []

      # オシレーター1: やや異なる波形特性で少しデチューン
      osc1 = Oscillator.new(:sine, sample_rate)
      osc1.harmonics = [
        [1.0, 0.8],    # 基本波 (80%)
        [2.0, 0.4],    # 第2倍音 (40%)
        [3.0, 0.2],    # 第3倍音 (20%)
      ]
      @oscillators << osc1

      # オシレーター2: 柔らかい音色のパルス波（デチューン）
      osc2 = Oscillator.new(:pulse, sample_rate)
      osc2.harmonics = [
        [1.0, 0.3],    # 基本波 (30% - 控えめ)
        [2.0, 0.1],    # 第2倍音 (10%)
      ]
      @oscillators << osc2

      # オシレーターの混合比率 [メイン, オシレーター1, オシレーター2]
      # 合計が1.0を超えると音量が上がりすぎる可能性があるため、注意
      @oscillator_mix = [0.6, 0.25, 0.15]

      # デチューン値（セント単位 - 100セント = 半音）
      @detune_cents = [0, 5, -7]  # メイン, オシレーター1, オシレーター2

      # フィルター設定
      @vcf.low_pass_cutoff = 5000.0  # 高めのカットオフ
      @vcf.high_pass_cutoff = 100.0  # 低域もある程度通す

      # アクセス可能なパラメータ
      @filter_cutoff = 5000.0
      @filter_resonance = 0.1  # 共鳴は控えめ

      # ピアノ音色の調整パラメータ
      @brightness = 0.7  # 明るさ（0.0-1.0）
      @hardness = 0.5    # 硬さ（0.0-1.0）

      # 基準ノート（C3 = ミドルC）
      @base_note = Note.new.set_by_midi(24)
    end

    # @param midi_note [Integer] MIDIノート番号
    # @param velocity [Integer] ベロシティ値（0-127）
    def note_on(midi_note, velocity)
      new_note = Note.new
      semitone_diff = midi_note - @base_note.midi_note
      new_note.set_by_midi(semitone_diff)

      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      # ベロシティ（強さ）によって音色が変化する挙動を再現
      vel_normalized = velocity / 127.0
      new_note.velocity = vel_normalized

      # ベロシティに応じてエンベロープと音色を動的に調整
      # 強く弾くほどアタックが速く、ディケイが長くなる
      dynamic_attack = @envelope.attack * (1.0 - (vel_normalized * 0.3))
      dynamic_decay = @envelope.decay * (1.0 + (vel_normalized * 0.5))

      # ノートごとにエンベロープのコピーを作成して調整
      new_note.custom_envelope = @envelope.dup
      new_note.custom_envelope.attack = dynamic_attack
      new_note.custom_envelope.decay = dynamic_decay

      # ベロシティに応じたフィルターカットオフの調整
      # 強く弾くほど明るい音になる
      new_note.filter_cutoff = @filter_cutoff * (1.0 + (vel_normalized * @brightness))

      @active_notes[midi_note] = new_note

      note_name = new_note.name + new_note.octave.to_s
      puts "piano note_on: midi_note=#{midi_note} (#{note_name}), velocity=#{velocity}, frequency=#{new_note.frequency.round(2)}Hz"
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      samples = Array.new(buffer_size, 0.0)

      start_sample_index = @global_sample_count
      active_note_count = 0

      @active_notes.each_value do |note|
        # メインオシレーターの波形生成
        main_wave = @oscillator.generate_wave(note, buffer_size)

        # 追加のオシレーターの波形を生成
        additional_waves = []

        @oscillators.each_with_index do |osc, idx|
          # デチューン用に一時的なノートを作成
          detuned_note = note.dup

          # デチューン適用（セント値をピッチ比に変換）
          if @detune_cents[idx + 1] != 0
            cent_ratio = 2.0 ** (@detune_cents[idx + 1] / 1200.0)
            detuned_freq = note.frequency * cent_ratio

            # 周波数だけを調整（位相などは元のノートと同じ）
            class << detuned_note
              attr_accessor :detuned_frequency
              alias_method :original_frequency, :frequency

              def frequency
                @detuned_frequency || original_frequency
              end
            end

            detuned_note.detuned_frequency = detuned_freq
          end

          # デチューンしたノートで波形生成
          additional_waves << osc.generate_wave(detuned_note, buffer_size)
        end

        # すべての波形にエンベロープを適用
        all_waves = [main_wave] + additional_waves

        all_waves.each_with_index do |wave, wave_idx|
          wave.each_with_index do |sample_val, idx|
            current_sample_index = start_sample_index + idx
            env_val = if note.custom_envelope
                        note.custom_envelope.apply_envelope(note, current_sample_index, @sample_rate)
                      else
                        @envelope.apply_envelope(note, current_sample_index, @sample_rate)
                      end

            # 適切なミックス比率を適用
            wave[idx] = sample_val * env_val * @oscillator_mix[wave_idx]
          end
        end

        # すべての波形を合成
        combined_wave = Array.new(buffer_size, 0.0)
        all_waves.each do |wave|
          combined_wave = combined_wave.zip(wave).map { |s1, s2| s1 + s2 }
        end

        # ノート固有のフィルターカットオフを適用
        @vcf.resonance = @filter_resonance
        filter_cutoff = note.filter_cutoff || @filter_cutoff
        @vcf.low_pass_cutoff = filter_cutoff
        combined_wave = @vcf.process(combined_wave, :low_pass)

        # 高音域のキーの場合、高域を強調するための追加フィルタリング
        if note.midi_note > 80  # 高音域の場合
          high_emphasis = 1.0 + ((note.midi_note - 80) * 0.02)  # 高音になるほど強調
          combined_wave.map! { |s| s * high_emphasis }
        end

        # 低音域のキーの場合、低域を強調
        if note.midi_note < 48  # 低音域の場合
          low_emphasis = 1.0 + ((48 - note.midi_note) * 0.03)  # 低音になるほど強調
          combined_wave.map! { |s| s * low_emphasis }
        end

        samples = samples.zip(combined_wave).map { |s1, s2| s1 + s2 }
        has_sound = combined_wave.any? { |sample| sample != 0.0 }
        active_note_count += 1 if has_sound
      end

      # マスターゲイン調整（複数の音がある場合は音量を調整）
      master_gain = 1.2  # 基本ゲイン
      if active_note_count > 1
        # 複数の音が同時に鳴っている場合にゲインを下げる
        master_gain *= (1.0 / Math.sqrt(active_note_count))
      end
      samples.map! { |sample| sample * master_gain }

      @global_sample_count += buffer_size

      cleanup_inactive_notes(buffer_size)

      samples
    end

    private

    def cleanup_inactive_notes(buffer_size)
      @active_notes.delete_if do |note_id, note|
        if note.note_off_sample_index
          env = note.custom_envelope || @envelope
          final_env = env.apply_envelope(note, @global_sample_count - 1, @sample_rate)
          final_env <= 0.0
        else
          false
        end
      end
    end
  end
end
