module Presets
  class MoogLead < Synthesizer
    # Moogフィルターのレゾナンス値（フィルター特有の鋭さ）
    attr_accessor :filter_resonance, :filter_cutoff, :filter_envelope_amount

    def initialize(sample_rate = 44100, amplitude = 1000)
      super(sample_rate, amplitude)

      # Moogシンセらしいエンベロープ設定
      # アタックはやや緩やかに、サステインは高めに設定
      @envelope.attack = 0.05    # 中程度のアタック - リードらしい立ち上がり
      @envelope.decay = 0.1      # 比較的速い減衰
      @envelope.sustain = 0.7    # 高めのサステインレベル - リード楽器向け
      @envelope.release = 0.2    # 適度なリリース

      # Moogシンセサイザーらしい倍音豊かな波形設定
      # 主にノコギリ波をベースに設定
      @oscillator.waveform = :sawtooth  # Moogの特徴的な音色に合わせてノコギリ波を選択

      # 倍音を追加して豊かな音にする
      @oscillator.harmonics = [
        [1.0, 1.0],      # 基本波
        [2.0, 0.5],      # 2倍音 (半分の音量)
        [3.0, 0.3],      # 3倍音 (30%の音量)
        [4.0, 0.2],      # 4倍音 (20%の音量)
      ]

      # フィルタ設定 - Moogらしいローパスフィルタの特性
      # 特徴的な温かみのある音色を作るためのフィルター設定
      @vcf.low_pass_cutoff = 1200.0   # やや低めのカットオフで温かみのある音に
      @vcf.high_pass_cutoff = 60.0    # 極低域のみをカット

      # Moog特有のフィルター設定用のパラメーター
      @filter_resonance = 0.8        # レゾナンス（0.0-1.0）- 特徴的なピークを作る
      @filter_cutoff = 1200.0        # 基本カットオフ周波数
      @filter_envelope_amount = 0.6  # フィルターエンベロープのかかり具合
      @filter_attack = 0.1           # フィルターエンベロープのアタック
      @filter_decay = 0.2            # フィルターエンベロープのディケイ

      # デチューン（複数オシレーターの微妙なずれ）設定
      @detune_amount = 0.005         # デチューン量 (5 cents程度)
    end

    def note_on(midi_note, velocity)
      new_note = Note.new
      new_note.set_by_midi(midi_note)
      new_note.phase = 0.0
      new_note.note_on_sample_index = @global_sample_count

      # ベロシティに応じた音量設定
      new_note.velocity = velocity.to_f / 127.0

      # ベロシティによってフィルターカットオフも変化させる
      # 強く弾くとブライトな音に、弱く弾くと丸い音に
      velocity_filter_mod = (velocity.to_f / 127.0) * 1500.0  # 最大1500Hz上昇
      @vcf.low_pass_cutoff = @filter_cutoff + velocity_filter_mod

      @active_notes[midi_note] = new_note
      puts "Moog lead note_on: #{midi_note}, velocity=#{velocity}, filter cutoff=#{@vcf.low_pass_cutoff}"
    end

    def generate(buffer_size)
      return Array.new(buffer_size, 0.0) if @active_notes.empty?

      # 個々の発音を合成する先
      samples = Array.new(buffer_size, 0.0)

      start_sample_index = @global_sample_count
      active_note_count = 0

      @active_notes.each_value do |note|
        # 基本オシレーターで波形生成
        wave1 = @oscillator.generate_wave(note, buffer_size)

        # デチューンした2つ目のオシレーター用に一時的なノートを作成
        # Noteクラスには frequency= がないので、別インスタンスで生成する
        detuned_note = Note.new
        detuned_note.set_by_midi(note.midi_note)
        # semitoneを直接調整してデチューン効果を出す（frequency=の代わり）
        detuned_semitone = note.midi_note - 69 + (@detune_amount * 100 / 100.0)
        detuned_note.instance_variable_set(:@semitone, detuned_semitone)
        detuned_note.phase = note.phase

        # デチューンしたノートで波形を生成
        wave2 = @oscillator.generate_wave(detuned_note, buffer_size)

        # 2つの波形をミックス
        wave = wave1.zip(wave2).map { |s1, s2| (s1 + s2) * 0.5 }

        wave.each_with_index do |sample_val, idx|
          current_sample_index = start_sample_index + idx

          # エンベロープを適用
          env_val = @envelope.apply_envelope(note, current_sample_index, @sample_rate)
          # velocity が nil の場合に備えて、デフォルト値を使う
          velocity_value = note.velocity.nil? ? 1.0 : note.velocity

          # サンプル値にエンベロープとベロシティを適用
          wave[idx] = sample_val * env_val * velocity_value
        end

        # フィルタ処理を適用（基本的なローパスフィルター）
        wave = @vcf.process(wave, :low_pass)

        # 各ノートの波形を足し合わせる
        samples = samples.zip(wave).map { |s1, s2| s1 + s2 }

        # 音が出ているノートをカウント
        has_sound = false
        wave.each do |sample|
          if sample != 0.0
            has_sound = true
            break
          end
        end
        active_note_count += 1 if has_sound
      end

      # 複数音発音時の音量調整
      master_gain = 5.0
      if active_note_count > 1
        master_gain *= (1.0 / Math.sqrt(active_note_count))
      end

      # 最終的な音量調整（アンプリチュード適用）
      samples.map! { |sample| sample * master_gain * @amplitude }

      @global_sample_count += buffer_size
      cleanup_inactive_notes(buffer_size)

      samples
    end

    private

    def cleanup_inactive_notes(buffer_size)
      @active_notes.delete_if do |note_id, note|
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
